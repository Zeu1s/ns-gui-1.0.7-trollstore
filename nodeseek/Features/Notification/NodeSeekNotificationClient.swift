//
//  NodeSeekNotificationClient.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import Foundation

protocol NodeSeekNotificationClientProtocol {
    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount
    func loadAtMe() async throws -> [NodeSeekNotificationRecord]
    func loadReplies() async throws -> [NodeSeekNotificationRecord]
    func loadMessageConversations() async throws -> [NodeSeekMessageConversationRecord]
    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws
    func markAllViewed(tab: NodeSeekNotificationTab) async throws
}

final class NodeSeekNotificationClient: NodeSeekNotificationClientProtocol {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()
    private let cookiePreparer: @Sendable () async -> Void
    private let markViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting

    /// 通知页会并发请求未读数和列表；合并短时间内重复的 WebKit Cookie 同步，
    /// 避免切换到私信时再次等待同一轮同步。
    @MainActor private static let defaultCookieSession = NodeSeekCookieSession()
    @MainActor private static var cookiePreparationTask: Task<Void, Never>?
    @MainActor private static var lastCookiePreparationAt: Date?
    private static let cookiePreparationReuseInterval: TimeInterval = 2

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        cookiePreparer: @escaping @Sendable () async -> Void = {
            await NodeSeekNotificationClient.prepareDefaultHTTPLoad()
        },
        markViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting = WebViewNodeSeekNotificationMarkViewedSubmitter()
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookiePreparer = cookiePreparer
        self.markViewedSubmitter = markViewedSubmitter
    }

    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount {
        let request = makeRequest(
            path: "/api/notification/unread-count",
            referer: NodeSeekNotificationTab.atMe.webURL
        )
        let response = try await decode(UnreadCountResponse.self, from: request)
        guard response.success else {
            logBusinessFailure(for: request, message: nil)
            throw NodeSeekNotificationClientError.unsuccessfulResponse(nil)
        }
        return response.unreadCount
    }

    func loadAtMe() async throws -> [NodeSeekNotificationRecord] {
        let request = makeRequest(
            path: "/api/notification/at-me/list",
            referer: NodeSeekNotificationTab.atMe.webURL
        )
        let response = try await decode(NotificationListResponse.self, from: request)
        guard response.success else {
            logBusinessFailure(for: request, message: response.message)
            throw NodeSeekNotificationClientError.unsuccessfulResponse(response.message)
        }
        return response.data
    }

    func loadReplies() async throws -> [NodeSeekNotificationRecord] {
        let request = makeRequest(
            path: "/api/notification/reply-to-me/list",
            referer: NodeSeekNotificationTab.reply.webURL
        )
        let response = try await decode(NotificationListResponse.self, from: request)
        guard response.success else {
            logBusinessFailure(for: request, message: response.message)
            throw NodeSeekNotificationClientError.unsuccessfulResponse(response.message)
        }
        return response.data
    }

    func loadMessageConversations() async throws -> [NodeSeekMessageConversationRecord] {
        let request = makeRequest(
            path: "/api/notification/message/list",
            referer: NodeSeekNotificationTab.message.webURL
        )
        let response = try await decode(MessageListResponse.self, from: request)
        guard response.success else {
            logBusinessFailure(for: request, message: response.message)
            throw NodeSeekNotificationClientError.unsuccessfulResponse(response.message)
        }
        return response.msgArray
    }

    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws {
        let normalizedIDs = ids.filter { $0 > 0 }
        guard normalizedIDs.isEmpty == false else { return }

        let request = try NodeSeekNotificationMarkViewedRequest.single(ids: normalizedIDs, tab: tab)
        try await markViewedSubmitter.submit(request, referer: tab.webURL)
    }

    func markAllViewed(tab: NodeSeekNotificationTab) async throws {
        let request = NodeSeekNotificationMarkViewedRequest.all(tab: tab)
        try await markViewedSubmitter.submit(request, referer: tab.webURL)
    }

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        body: Data? = nil,
        referer: URL
    ) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems
        let url = components?.url ?? baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: referer)
        return request
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from request: URLRequest) async throws -> Response {
        let startedAt = Date()
        let method = request.notificationLogMethod
        let target = request.notificationLogURL
        await cookiePreparer()
        // 诊断：通知的 500 与收藏的 500 是同一类（站点游客态统一回
        // USER NOT FOUND / 57 字节），先确认 session cookie 有没有真的带上。
        let attachedCookies = HTTPCookieStorage.shared.cookies(for: request.url ?? NodeSeekSite.baseURL)?
            .map(\.name) ?? []
        AppLog.info(.service, "通知接口请求开始 method=\(method), url=\(target), 已附带cookie=\(attachedCookies.joined(separator: ","))")

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            AppLog.error(
                .service,
                "通知接口请求失败 method=\(method), url=\(target), error=\(error.localizedDescription), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
            )
            throw error
        }

        if let httpResponse = urlResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            let snippet = String(decoding: data.prefix(240), as: UTF8.self)
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            AppLog.warning(
                .service,
                "通知接口响应异常 method=\(method), url=\(target), status=\(httpResponse.statusCode), bytes=\(data.count), body=\(snippet), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
            )
            // URLSession 被 Cloudflare 指纹封锁（403/限流 429 拦截页）、或站点回 500
            // （游客态 USER NOT FOUND）时，改用 WebView 同源 fetch 取同一个 JSON 接口。
            // 但 502/503/504 不回退：那是站点自己的 nginx 在那一刻回不动，跟我们的
            // 登录态和指纹都无关。真机日志两次实测：503 走同源 fetch 回退后拿到的
            // 还是 503（663 字节 → 656 字节），白付一次隐藏 WebView 整页加载和 2.7 秒。
            let status = httpResponse.statusCode
            let isSiteOutage = status == 502 || status == 503 || status == 504
            if status == 403 || status == 429 || ((500..<600).contains(status) && !isSiteOutage) {
                return try await decodeViaWebView(type, request: request)
            }
            throw NodeSeekNotificationClientError.httpStatus(status)
        }

        do {
            let decoded = try decoder.decode(Response.self, from: data)
            let status = httpStatusDescription(from: urlResponse)
            AppLog.info(
                .service,
                "通知接口响应成功 method=\(method), url=\(target), status=\(status), bytes=\(data.count), responseType=\(Response.self), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
            )
            return decoded
        } catch {
            let status = httpStatusDescription(from: urlResponse)
            AppLog.error(
                .service,
                "通知接口解析失败 method=\(method), url=\(target), status=\(status), bytes=\(data.count), responseType=\(Response.self), error=\(error.localizedDescription), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
            )
            throw error
        }
    }

    /// 通知接口 WebView 同源 fetch 回退。
    private func decodeViaWebView<Response: Decodable>(_ type: Response.Type, request: URLRequest) async throws -> Response {
        let target = request.notificationLogURL
        let method = request.notificationLogMethod
        AppLog.warning(.service, "通知接口 WebView 同源 fetch 回退: method=\(method), url=\(target)")
        guard let apiPath = request.url?.absoluteString else {
            throw NodeSeekNotificationClientError.unsuccessfulResponse(nil)
        }

        let response = try await WebViewJSONAPIClient.fetchDecodable(
            type,
            apiPath: apiPath,
            referer: NodeSeekNotificationTab.atMe.webURL,
            method: method,
            body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) },
            decoder: decoder,
            // 站点接口要求 x-dynamic-sign，缺签名时服务端直接 500。
            // 只有通知这条链路开：getInfo 等已在无签名下工作正常，
            // 不给它们引入新的校验面。
            signed: true,
            // referer 是 /notification#/atMe 这类单页应用，页面没有帖子列表标记，
            // 开着会让 ChallengeDetector 把它误判成挑战页：先白跑 10 轮
            // ×1.2 秒轮询（真机日志里 6 次跑满），再在脚本执行前短路返回空 body。
            requireCleanPage: false
        )
        return response
    }

    private func logBusinessFailure(for request: URLRequest, message: String?) {
        AppLog.warning(
            .service,
            "通知接口业务失败 method=\(request.notificationLogMethod), url=\(request.notificationLogURL), message=\(message ?? "nil")"
        )
    }

    private func httpStatusDescription(from response: URLResponse) -> String {
        guard let httpResponse = response as? HTTPURLResponse else { return "nil" }
        return String(httpResponse.statusCode)
    }

    @MainActor
    private static func prepareDefaultHTTPLoad() async {
        let now = Date()
        if let lastCookiePreparationAt,
           now.timeIntervalSince(lastCookiePreparationAt) < cookiePreparationReuseInterval {
            return
        }
        if let cookiePreparationTask {
            await cookiePreparationTask.value
            return
        }

        let task = Task { @MainActor in
            await defaultCookieSession.prepareHTTPLoad()
        }
        cookiePreparationTask = task
        await task.value
        cookiePreparationTask = nil
        lastCookiePreparationAt = Date()
    }
}

private extension URLRequest {
    var notificationLogMethod: String {
        httpMethod ?? "GET"
    }

    var notificationLogURL: String {
        url?.absoluteString ?? "nil"
    }
}

enum NodeSeekNotificationClientError: LocalizedError, Equatable {
    case httpStatus(Int)
    case unsuccessfulResponse(String?)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessfulResponse(let message):
            return message ?? "接口返回失败"
        }
    }
}

private extension NodeSeekNotificationTab {
    nonisolated var markViewedPath: String {
        switch self {
        case .atMe:
            return "/api/notification/at-me/markViewed"
        case .reply:
            return "/api/notification/reply-to-me/markViewed"
        case .message:
            return "/api/notification/message/markViewed"
        }
    }
}

private struct NotificationListResponse: Decodable {
    let success: Bool
    let data: [NodeSeekNotificationRecord]
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case data
        case atList
        case replyList
        case notifications
        case list
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        data = try container.decodeIfPresent([NodeSeekNotificationRecord].self, forKey: .data)
            ?? container.decodeIfPresent([NodeSeekNotificationRecord].self, forKey: .atList)
            ?? container.decodeIfPresent([NodeSeekNotificationRecord].self, forKey: .replyList)
            ?? container.decodeIfPresent([NodeSeekNotificationRecord].self, forKey: .notifications)
            ?? container.decodeIfPresent([NodeSeekNotificationRecord].self, forKey: .list)
            ?? []
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

private struct MessageListResponse: Decodable {
    let success: Bool
    let msgArray: [NodeSeekMessageConversationRecord]
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case msgArray
        case messageList = "message_list"
        case messages
        case conversations
        case list
        case data
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        msgArray = Self.records(in: container, keys: [.msgArray, .messageList, .messages, .conversations, .list])
            ?? Self.records(in: container, keys: [.data])
            ?? (try? container.decodeIfPresent(MessageListData.self, forKey: .data))?.records
            ?? []
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    private static func records(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> [NodeSeekMessageConversationRecord]? {
        for key in keys where container.contains(key) {
            if let values = try? container.decode([FailableDecodable<NodeSeekMessageConversationRecord>].self, forKey: key) {
                return values.compactMap(\.value)
            }
        }
        return nil
    }

    private struct MessageListData: Decodable {
        let records: [NodeSeekMessageConversationRecord]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            records = MessageListResponse.records(
                in: container,
                keys: [.msgArray, .messageList, .messages, .conversations, .list]
            ) ?? []
        }
    }
}

private struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct UnreadCountResponse: Decodable {
    let success: Bool
    let unreadCount: NodeSeekNotificationUnreadCount
}

extension NodeSeekNotificationUnreadCount: Decodable {
    private enum CodingKeys: String, CodingKey {
        case message
        case atMe
        case reply
        case all
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(Int.self, forKey: .message) ?? 0
        atMe = try container.decodeIfPresent(Int.self, forKey: .atMe) ?? 0
        reply = try container.decodeIfPresent(Int.self, forKey: .reply) ?? 0
        all = try container.decodeIfPresent(Int.self, forKey: .all) ?? message + atMe + reply
    }
}

nonisolated struct NodeSeekNotificationMarkViewedRequest: Equatable {
    let apiPath: String
    let bodyJSON: String?

    static func single(
        ids: [Int],
        tab: NodeSeekNotificationTab,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> NodeSeekNotificationMarkViewedRequest {
        let body: NotificationMarkBody
        switch tab {
        case .atMe:
            body = NotificationMarkBody(atMe: ids)
        case .reply:
            body = NotificationMarkBody(replys: ids)
        case .message:
            body = NotificationMarkBody(messages: ids)
        }
        let data = try encoder.encode(body)
        return NodeSeekNotificationMarkViewedRequest(
            apiPath: tab.markViewedPath,
            bodyJSON: String(data: data, encoding: .utf8)
        )
    }

    static func all(tab: NodeSeekNotificationTab) -> NodeSeekNotificationMarkViewedRequest {
        NodeSeekNotificationMarkViewedRequest(
            apiPath: "\(tab.markViewedPath)?all=true",
            bodyJSON: nil
        )
    }
}

nonisolated private struct NotificationMarkBody: Encodable {
    let atMe: [Int]?
    let replys: [Int]?
    let messages: [Int]?

    init(atMe: [Int]? = nil, replys: [Int]? = nil, messages: [Int]? = nil) {
        self.atMe = atMe
        self.replys = replys
        self.messages = messages
    }
}
