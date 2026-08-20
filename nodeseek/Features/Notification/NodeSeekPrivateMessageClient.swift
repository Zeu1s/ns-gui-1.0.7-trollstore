//
//  NodeSeekPrivateMessageClient.swift
//  nodeseek
//

import Foundation

nonisolated struct NodeSeekPrivateMessage: Decodable, Equatable, Sendable {
    let id: Int
    let senderID: Int
    let receiverID: Int
    let content: String
    let createdAt: Date
    let isMarkdown: Bool

    var senderAvatarURL: URL {
        NodeSeekNotificationURLBuilder.avatarURL(memberID: senderID)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case senderID = "sender_id"
        case receiverID = "receiver_id"
        case content
        case createdAt = "created_at"
        case isMarkdown = "is_markdown"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        senderID = try container.decode(Int.self, forKey: .senderID)
        receiverID = try container.decode(Int.self, forKey: .receiverID)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        if let boolValue = try? container.decode(Bool.self, forKey: .isMarkdown) {
            isMarkdown = boolValue
        } else {
            isMarkdown = ((try? container.decode(Int.self, forKey: .isMarkdown)) ?? 0) != 0
        }
        let dateText = try container.decode(String.self, forKey: .createdAt)
        guard let parsedDate = NodeSeekNotificationDateParser.date(from: dateText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Invalid private-message date: \(dateText)"
            )
        }
        createdAt = parsedDate
    }
}

nonisolated struct NodeSeekPrivateMessageConversation: Equatable, Sendable {
    let participantID: Int
    let participantName: String?
    let messages: [NodeSeekPrivateMessage]
}

protocol NodeSeekPrivateMessageLoading {
    func loadConversation(with userID: Int) async throws -> NodeSeekPrivateMessageConversation
    func sendMessage(to userID: Int, content: String, markdown: Bool) async throws
}

enum NodeSeekPrivateMessageClientError: LocalizedError, Equatable {
    case httpStatus(Int)
    case unsuccessfulResponse(String?)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessfulResponse(let message):
            return message ?? "私信接口返回失败"
        }
    }
}

final class NodeSeekPrivateMessageClient: NodeSeekPrivateMessageLoading {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()
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

    func loadConversation(with userID: Int) async throws -> NodeSeekPrivateMessageConversation {
        let request = makeRequest(
            path: "/api/notification/message/with/\(userID)",
            referer: NodeSeekNotificationURLBuilder.webURL(fragment: "/message?mode=talk&to=\(userID)")
        )
        let response = try await decode(ConversationResponse.self, request: request)
        guard response.success else {
            throw NodeSeekPrivateMessageClientError.unsuccessfulResponse(response.message)
        }
        return NodeSeekPrivateMessageConversation(
            participantID: response.talkTo?.memberID ?? userID,
            participantName: response.talkTo?.memberName,
            messages: response.messages.sorted { $0.createdAt < $1.createdAt }
        )
    }

    func sendMessage(to userID: Int, content: String, markdown: Bool) async throws {
        let body = SendMessageBody(receiverUid: userID, content: content, markdown: markdown)
        let data = try JSONEncoder().encode(body)
        let request = makeRequest(
            path: "/api/notification/message/send",
            method: "POST",
            body: data,
            referer: NodeSeekNotificationURLBuilder.webURL(fragment: "/message?mode=talk&to=\(userID)")
        )
        let response = try await decode(SendMessageResponse.self, request: request)
        guard response.success else {
            throw NodeSeekPrivateMessageClientError.unsuccessfulResponse(response.message)
        }
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil, referer: URL) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        let url = components?.url ?? baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: referer)
        return request
    }

    private func decode<Response: Decodable>(_ type: Response.Type, request: URLRequest) async throws -> Response {
        await cookiePreparer()
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw NodeSeekPrivateMessageClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct ConversationResponse: Decodable {
    let success: Bool
    let message: String?
    let talkTo: ConversationParticipant?
    let messages: [NodeSeekPrivateMessage]

    private enum CodingKeys: String, CodingKey {
        case success
        case message
        case talkTo
        case messages = "msgArray"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        talkTo = try container.decodeIfPresent(ConversationParticipant.self, forKey: .talkTo)
        messages = try container.decodeIfPresent([NodeSeekPrivateMessage].self, forKey: .messages) ?? []
    }
}

private struct ConversationParticipant: Decodable {
    let memberID: Int
    let memberName: String?

    private enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case memberName = "member_name"
    }
}

private struct SendMessageBody: Encodable {
    let receiverUid: Int
    let content: String
    let markdown: Bool
}

private struct SendMessageResponse: Decodable {
    let success: Bool
    let message: String?
}
