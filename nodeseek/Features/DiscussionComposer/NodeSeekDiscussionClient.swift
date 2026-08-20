//
//  NodeSeekDiscussionClient.swift
//  nodeseek
//

import Foundation

nonisolated struct NodeSeekDiscussionDraft: Encodable, Equatable, Sendable {
    let title: String
    let content: String
    let category: String
    let rank: Int

    private enum CodingKeys: String, CodingKey {
        case title
        case content
        case category
        case rank
        case mode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(category, forKey: .category)
        try container.encode(rank, forKey: .rank)
        try container.encode("new-discussion", forKey: .mode)
    }
}

nonisolated struct NodeSeekDiscussionSubmission: Equatable, Sendable {
    let redirect: String?
    let redirectHash: String?
}

protocol NodeSeekDiscussionSubmitting {
    func submit(_ draft: NodeSeekDiscussionDraft) async throws -> NodeSeekDiscussionSubmission
}

enum NodeSeekDiscussionClientError: LocalizedError, Equatable {
    case httpStatus(Int)
    case notLoggedIn
    case unsuccessfulResponse(String?)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "发布失败：HTTP \(status)"
        case .notLoggedIn:
            return "请先登录 NodeSeek 后再发布。"
        case .unsuccessfulResponse(let message):
            return message ?? "发布失败，请稍后重试。"
        }
    }
}

final class NodeSeekDiscussionClient: NodeSeekDiscussionSubmitting {
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

    func submit(_ draft: NodeSeekDiscussionDraft) async throws -> NodeSeekDiscussionSubmission {
        let payload = try JSONEncoder().encode(draft)
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/content/new-discussion"
        let url = components?.url ?? baseURL.appendingPathComponent("api/content/new-discussion")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: NodeSeekSite.newDiscussionURL)
        request.setValue(Self.makeCSRFToken(length: 16), forHTTPHeaderField: "csrf-token")

        await cookiePreparer()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NodeSeekDiscussionClientError.unsuccessfulResponse(nil)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NodeSeekDiscussionClientError.httpStatus(httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(SubmitResponse.self, from: data)
        guard result.success else {
            if Self.isLoginMessage(result.message) {
                throw NodeSeekDiscussionClientError.notLoggedIn
            }
            throw NodeSeekDiscussionClientError.unsuccessfulResponse(result.message)
        }
        return NodeSeekDiscussionSubmission(redirect: result.redirect, redirectHash: result.redirectHash)
    }

    private static func makeCSRFToken(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).compactMap { _ in
            alphabet.randomElement(using: &generator)
        })
    }

    private static func isLoginMessage(_ message: String?) -> Bool {
        let normalized = message?.lowercased() ?? ""
        return normalized.contains("user not found")
            || normalized.contains("not login")
            || normalized.contains("未登录")
            || normalized.contains("请先登录")
    }
}

private struct SubmitResponse: Decodable {
    let success: Bool
    let message: String?
    let redirect: String?
    let redirectHash: String?
}
