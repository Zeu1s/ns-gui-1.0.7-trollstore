//
//  NodeSeekUserRelationshipClient.swift
//  nodeseek
//

import Foundation

nonisolated struct NodeSeekTransferRecipient: Equatable, Sendable {
    let userID: Int
    let username: String?
}

protocol NodeSeekUserRelationshipManaging {
    func setFollowing(userID: Int, following: Bool) async throws
    func prepareStardustTransfer(to userID: Int) async throws -> NodeSeekTransferRecipient
    func sendStardustTransfer(to userID: Int, amount: Int, referenceID: Int) async throws
}

enum NodeSeekUserRelationshipClientError: LocalizedError, Equatable {
    case invalidAmount
    case httpStatus(Int)
    case unsuccessfulResponse(String?)

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "转账数量必须大于 0。"
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessfulResponse(let message):
            return message ?? "接口返回失败"
        }
    }
}

final class NodeSeekUserRelationshipClient: NodeSeekUserRelationshipManaging {
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

    func setFollowing(userID: Int, following: Bool) async throws {
        let body = try JSONEncoder().encode(FollowBody(followedMemberID: userID))
        let response: BasicResponse = try await decode(
            BasicResponse.self,
            path: following ? "/api/fans/add" : "/api/fans/del",
            body: body,
            referer: profileURL(for: userID)
        )
        guard response.success else {
            throw NodeSeekUserRelationshipClientError.unsuccessfulResponse(response.message)
        }
    }

    func prepareStardustTransfer(to userID: Int) async throws -> NodeSeekTransferRecipient {
        let body = try JSONEncoder().encode(TransferPrepareBody(receiverID: userID, origin: baseURL.absoluteString))
        let response: TransferPrepareResponse = try await decode(
            TransferPrepareResponse.self,
            path: "/api/stardust/payment-prepare",
            body: body,
            referer: profileURL(for: userID)
        )
        guard response.success else {
            throw NodeSeekUserRelationshipClientError.unsuccessfulResponse(response.message)
        }
        return NodeSeekTransferRecipient(userID: userID, username: response.receiverName)
    }

    func sendStardustTransfer(to userID: Int, amount: Int, referenceID: Int) async throws {
        guard amount > 0 else { throw NodeSeekUserRelationshipClientError.invalidAmount }
        let body = try JSONEncoder().encode(
            TransferSendBody(memberID: userID, diff: amount, refID: max(0, referenceID))
        )
        let response: BasicResponse = try await decode(
            BasicResponse.self,
            path: "/api/stardust/send",
            body: body,
            referer: profileURL(for: userID)
        )
        guard response.success else {
            throw NodeSeekUserRelationshipClientError.unsuccessfulResponse(response.message)
        }
    }

    private func decode<Response: Decodable>(
        _ type: Response.Type,
        path: String,
        body: Data,
        referer: URL
    ) async throws -> Response {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        let url = components?.url ?? baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: referer)
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        await cookiePreparer()
        let (data, urlResponse) = try await session.data(for: request)
        if let response = urlResponse as? HTTPURLResponse,
           (200..<300).contains(response.statusCode) == false {
            throw NodeSeekUserRelationshipClientError.httpStatus(response.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func profileURL(for userID: Int) -> URL {
        baseURL
            .appendingPathComponent("space")
            .appendingPathComponent("\(userID)")
    }
}

private struct FollowBody: Encodable {
    let followedMemberID: Int

    private enum CodingKeys: String, CodingKey {
        case followedMemberID = "followed_member_id"
    }
}

private struct TransferPrepareBody: Encodable {
    let receiverID: Int
    let origin: String

    private enum CodingKeys: String, CodingKey {
        case receiverID = "receiver_id"
        case origin
    }
}

private struct TransferSendBody: Encodable {
    let memberID: Int
    let diff: Int
    let refID: Int

    private enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case diff
        case refID = "ref_id"
    }
}

private struct BasicResponse: Decodable {
    let success: Bool
    let message: String?
}

private struct TransferPrepareResponse: Decodable {
    let success: Bool
    let message: String?
    let receiverName: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case message
        case receiverName = "receiver_name"
    }
}
