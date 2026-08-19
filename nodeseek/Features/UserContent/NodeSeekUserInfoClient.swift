//
//  NodeSeekUserInfoClient.swift
//  nodeseek
//

import Foundation

nonisolated struct NodeSeekUserInfo: Equatable, Sendable {
    let userID: Int
    let username: String?
    let createdAt: Date?
    let joinDays: Int
    let level: Int
    let coin: Int
    let stardust: Int
    let nPost: Int
    let nComment: Int

    var badgeText: String {
        "Lv \(level) · \(joinDays)天"
    }
}

enum NodeSeekUserInfoClientError: LocalizedError {
    case unsuccessfulResponse(String?)
    case missingDetail
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unsuccessfulResponse(let message):
            return message ?? "用户资料接口返回失败。"
        case .missingDetail:
            return "用户资料接口缺少资料数据。"
        case .httpStatus(let statusCode):
            return "用户资料接口状态码 \(statusCode)。"
        }
    }
}

protocol NodeSeekUserInfoLoading {
    func loadUserInfo(userID: Int) async throws -> NodeSeekUserInfo
}

final class NodeSeekUserInfoClient: NodeSeekUserInfoLoading {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let cookiePreparer: @Sendable () async -> Void

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        cookiePreparer: @escaping @Sendable () async -> Void = {
            await NodeSeekUserInfoClient.prepareDefaultHTTPLoad()
        }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookiePreparer = cookiePreparer
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    private static func prepareDefaultHTTPLoad() async {
        await NodeSeekCookieSession().prepareHTTPLoad()
    }

    func loadUserInfo(userID: Int) async throws -> NodeSeekUserInfo {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/account/getInfo/\(userID)"
        let url = components?.url ?? baseURL.appendingPathComponent("/api/account/getInfo/\(userID)")
        var refererComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        refererComponents?.path = "/space/\(userID)"
        let referer = refererComponents?.url ?? baseURL
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        WebRequestFingerprint.applyJSONHeaders(
            to: &request,
            referer: referer
        )

        await cookiePreparer()
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            throw error
        }

        if let httpResponse = urlResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw NodeSeekUserInfoClientError.httpStatus(httpResponse.statusCode)
        }

        let response = try decoder.decode(UserInfoResponse.self, from: data)
        guard response.success else {
            throw NodeSeekUserInfoClientError.unsuccessfulResponse(response.message)
        }
        guard let detail = response.detail else {
            throw NodeSeekUserInfoClientError.missingDetail
        }

        let createdAt = Self.parseDate(detail.createdAt)
        let joinDays = Self.joinDays(from: createdAt)
        let coin = max(0, detail.coin ?? 0)
        let level = detail.rank ?? Self.computedLevel(coin: coin)
        return NodeSeekUserInfo(
            userID: userID,
            username: detail.username,
            createdAt: createdAt,
            joinDays: joinDays,
            level: max(0, level),
            coin: coin,
            stardust: max(0, detail.stardust ?? 0),
            nPost: max(0, detail.nPost ?? 0),
            nComment: max(0, detail.nComment ?? 0)
        )
    }

    private static func computedLevel(coin: Int) -> Int {
        min(6, Int(sqrt(Double(max(0, coin))) / 10))
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, raw.isEmpty == false else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func joinDays(from date: Date?) -> Int {
        guard let date else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return max(1, days)
    }
}

private struct UserInfoResponse: Decodable {
    let success: Bool
    let message: String?
    let detail: Detail?

    struct Detail: Decodable {
        let username: String?
        let createdAt: String?
        let coin: Int?
        let stardust: Int?
        let nPost: Int?
        let nComment: Int?
        let rank: Int?
    }
}