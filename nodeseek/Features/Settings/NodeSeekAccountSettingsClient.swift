//
//  NodeSeekAccountSettingsClient.swift
//  nodeseek
//

import Foundation
import Kanna

nonisolated struct NodeSeekAccountEditableProfile: Equatable, Sendable {
    let bio: String
    let signature: String
    let readme: String
}

protocol NodeSeekAccountSettingsManaging {
    func loadProfile(userID: Int) async throws -> NodeSeekAccountEditableProfile
    func updateProfile(_ profile: NodeSeekAccountEditableProfile) async throws
    func uploadAvatarPNG(_ data: Data) async throws
}

enum NodeSeekAccountSettingsClientError: LocalizedError, Equatable {
    case httpStatus(Int)
    case unsuccessfulResponse(String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessfulResponse(let message):
            return message ?? "账号设置接口返回失败"
        case .invalidResponse:
            return "账号设置接口返回格式异常"
        }
    }
}

final class NodeSeekAccountSettingsClient: NodeSeekAccountSettingsManaging {
    private let session: URLSession
    private let baseURL: URL
    private let cookiePreparer: @Sendable () async -> Void

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        cookiePreparer: @escaping @Sendable () async -> Void = {
            await NodeSeekCookieSession().prepareHTTPLoad()
        }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookiePreparer = cookiePreparer
    }

    func loadProfile(userID: Int) async throws -> NodeSeekAccountEditableProfile {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/account/getInfo/\(userID)"
        // 站点空间页 SPA 实测只调 getInfo?readme=1（不带 signature）；带 signature=1
        // 会被服务端 500 拒绝（他人资料场景），这正是 README 一直失败的根因。
        components?.queryItems = [
            URLQueryItem(name: "readme", value: "1")
        ]
        let url = components?.url ?? baseURL.appendingPathComponent("/api/account/getInfo/\(userID)?readme=1")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: settingsURL)

        let root: [String: Any]
        do {
            root = try await performJSONRequest(request)
        } catch NodeSeekAccountSettingsClientError.httpStatus(let status)
                where status == 403 || status == 429 || status == 500 || status == 503 {
            // URLSession 被 Cloudflare 指纹封锁（403/限流 429 拦截页）时，
            // 改用 WebView 同源 fetch 直接取同一个 getInfo JSON 接口。
            AppLog.warning(.account, "getInfo URLSession 被拦截(HTTP \(status))，改用 WebView 同源 fetch: uid=\(userID)")
            let response = try await WebViewJSONAPIClient.fetch(
                apiPath: "/api/account/getInfo/\(userID)?readme=1",
                referer: baseURL.appendingPathComponent("space/\(userID)")
            )
            guard response.statusCode.map({ (200..<300).contains($0) }) == true,
                  let json = response.json else {
                throw NodeSeekAccountSettingsClientError.httpStatus(response.statusCode ?? 0)
            }
            root = json
        }
        guard let detail = root["detail"] as? [String: Any] else {
            AppLog.warning(.account, "getInfo 响应无 detail: \(String(data: (try? JSONSerialization.data(withJSONObject: root)) ?? Data(), encoding: .utf8)?.prefix(400) ?? "")")
            throw NodeSeekAccountSettingsClientError.invalidResponse
        }
        if detail["readme"] == nil {
            AppLog.warning(.account, "getInfo 响应的 detail 无 readme 字段，keys: \(detail.keys.sorted().joined(separator: ","))")
        } else {
            AppLog.info(.account, "getInfo 解析成功: uid=\(userID), readmeLength=\((detail["readme"] as? String)?.count ?? -1), keys=\(detail.keys.sorted().joined(separator: ","))")
        }
        return NodeSeekAccountEditableProfile(
            bio: Self.string(detail["bio"]),
            signature: Self.string(detail["signature_markdown"]),
            readme: Self.string(detail["readme"])
        )
    }

    /// 首选路径：URLSession 直接拉空间页 SSR（粉丝页 SSR 已证明 HTTP 通道可用），
    /// Nuxt 服务端渲染会把 readme 输出在 <div class="readme post-content"> 里，
    /// 用 Kanna 提取即可，完全免去 WebView 渲染与挑战风险。
    func loadReadmeViaSpaceSSR(userID: Int) async -> String? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/space/\(userID)"
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        WebRequestFingerprint.applyHTMLHeaders(to: &request)
        do {
            await cookiePreparer()
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                AppLog.info(.account, "空间页 SSR 读取失败: uid=\(userID), status=\((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }
            guard let document = try? HTML(html: html, encoding: .utf8),
                  let readmeNode = document.at_css("div.readme") else {
                AppLog.info(.account, "空间页 SSR 未含 readme 容器: uid=\(userID), htmlLength=\(html.count)")
                return nil
            }
            let innerHTML = readmeNode.innerHTML ?? ""
            let text = (readmeNode.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else {
                AppLog.info(.account, "空间页 SSR readme 为空: uid=\(userID)")
                return nil
            }
            AppLog.info(.account, "空间页 SSR 提取 readme 成功: uid=\(userID), htmlLength=\(innerHTML.count)")
            return innerHTML.isEmpty ? text : innerHTML
        } catch {
            AppLog.info(.account, "空间页 SSR 读取异常: uid=\(userID), \(error.localizedDescription)")
            return nil
        }
    }

    /// 空间页兜底：getInfo 拿不到 readme（字段为空/接口被拦）时，
    /// 用隐藏 WebView 打开 /space/{uid}#/general，读取页面上渲染好的 readme 区块。
    /// 返回 HTML（优先）或纯文本，由 ProfileReadmeCell 的结构化 HTML 通道渲染。
    /// 挑战页/加载失败自动重试一次（Cloudflare 挑战二次加载常可直接通过）。
    func loadReadmeViaSpacePage(userID: Int) async -> String? {
        let pageURL = baseURL.appendingPathComponent("space/\(userID)")
        for attempt in 0...1 {
            do {
                let object = try await withHiddenWebViewPageActionLoader(
                    logMessage: "准备通过隐藏 WebView 读取空间页 readme: uid=\(userID), attempt=\(attempt + 1)"
                ) { loader in
                try await loader.runPageAutomationScript(
                    pageURL: pageURL,
                    source: SpaceReadmeAutomationScript.source,
                    arguments: ["timeoutMs": 6_000],
                    timeoutInterval: 12,
                    actionName: "空间页 Readme",
                    requireCleanPage: false
                )
                }
                if let diagnose = object["diagnose"] as? [String: Any] {
                    AppLog.warning(.account, "空间页 readme 未命中诊断: \(diagnose)")
                }
                guard (object["ok"] as? Bool) == true else {
                    let reason = object["reason"] as? String ?? "unknown"
                    AppLog.warning(.account, "空间页 readme 脚本未命中: reason=\(reason), attempt=\(attempt + 1)")
                    guard attempt == 0 else { return nil }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                let html = object["html"] as? String ?? ""
                let text = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.isEmpty == false else { return nil }
                AppLog.info(.account, "空间页 readme 兜底命中: htmlLength=\(html.count), textLength=\(text.count)")
                return html.isEmpty ? text : html
            } catch {
                AppLog.warning(.account, "空间页 readme 兜底失败: attempt=\(attempt + 1), \(error.localizedDescription)")
                guard attempt == 0 else { return nil }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                continue
            }
        }
        return nil
    }

    func updateProfile(_ profile: NodeSeekAccountEditableProfile) async throws {
        let body: [String: String] = [
            "bio": profile.bio,
            "signature": profile.signature,
            "readme": profile.readme
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: endpoint(path: "/api/account/introduction"))
        request.httpMethod = "POST"
        request.httpBody = data
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: settingsURL)
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        _ = try await performJSONRequest(request)
    }

    func uploadAvatarPNG(_ data: Data) async throws {
        let boundary = "NodeSeekAvatarBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint(path: "/api/avatar/upload"))
        request.httpMethod = "POST"
        request.httpBody = Self.multipartBody(data: data, boundary: boundary)
        WebRequestFingerprint.applyImageHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(settingsURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("simple-token", forHTTPHeaderField: "x-csrf-challenge")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        _ = try await performJSONRequest(request)
    }

    private var settingsURL: URL {
        baseURL.appendingPathComponent("setting")
    }

    private func endpoint(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        return components?.url ?? baseURL.appendingPathComponent(path)
    }

    private func performJSONRequest(_ request: URLRequest) async throws -> [String: Any] {
        await cookiePreparer()
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw NodeSeekAccountSettingsClientError.httpStatus(httpResponse.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NodeSeekAccountSettingsClientError.invalidResponse
        }
        guard Self.bool(root["success"]) != false else {
            throw NodeSeekAccountSettingsClientError.unsuccessfulResponse(Self.string(root["message"]))
        }
        return root
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func string(_ value: Any?) -> String {
        guard let value = value as? String else { return "" }
        return value == "null" ? "" : value
    }

    private static func multipartBody(data: Data, boundary: String) -> Data {
        var body = Data()
        func append(_ value: String) {
            body.append(Data(value.utf8))
        }

        for (name, value) in [("token", "123456798"), ("name", "avatar")] {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"img\"; filename=\"avatar.png\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
