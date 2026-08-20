//
//  NodeSeekUserContentClient.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import Foundation

final class NodeSeekUserContentClient {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func loadCollections(page: Int, uid: Int) async throws -> [UserCollectionRecord] {
        let request = makeRequest(
            path: "/api/statistics/list-collection",
            queryItems: [URLQueryItem(name: "page", value: "\(max(1, page))")],
            refererUID: uid
        )
        let root = try await fetchJSON(from: request)
        let rows = try Self.requireRows(in: root, preferredNames: ["collections", "collectionList", "list", "data"])
        return rows.compactMap { row in
            guard let title = Self.string(row, ["title", "post_title", "subject"]),
                  let postID = Self.int(row, ["post_id", "postId", "pid", "id"]) else { return nil }
            return UserCollectionRecord(
                title: title,
                postID: postID,
                rank: Self.int(row, ["rank"]) ?? 0,
                authorName: Self.string(row, ["author_name", "member_name", "username", "user_name", "author", "commenter_name", "name"]),
                avatarURL: Self.string(row, ["avatar", "avatar_url", "avatar_path"]).flatMap {
                    URL(string: $0, relativeTo: self.baseURL)?.absoluteURL
                },
                viewCount: Self.int(row, ["view_count", "views", "click", "nView", "view_num", "click_count"]),
                replyCount: Self.int(row, ["reply_count", "comments", "comment_count", "nComment", "n_reply", "reply", "comment_num", "reply_num"]),
                lastActivityText: Self.string(row, ["last_reply_time", "last_reply_time_str", "last_activity", "last_activity_str", "updated_at", "last_comment_time"])
            )
        }
    }

    func loadComments(uid: Int, page: Int) async throws -> [UserCommentRecord] {
        let request = makeRequest(
            path: "/api/content/list-comments",
            queryItems: [
                URLQueryItem(name: "uid", value: "\(uid)"),
                URLQueryItem(name: "page", value: "\(max(1, page))")
            ],
            refererUID: uid
        )
        let root = try await fetchJSON(from: request)
        let rows = try Self.requireRows(in: root, preferredNames: ["comments", "commentList", "list", "data"])
        return rows.compactMap { row in
            guard let postID = Self.int(row, ["post_id", "postId", "pid"]) else { return nil }
            return UserCommentRecord(
                postID: postID,
                title: Self.string(row, ["title", "post_title", "subject"]) ?? "",
                rank: Self.int(row, ["rank"]) ?? 0,
                floorID: Self.int(row, ["floor_id", "floorId", "floor"]) ?? 1,
                text: Self.string(row, ["text", "content", "comment", "body", "excerpt"]) ?? ""
            )
        }
    }

    func loadDiscussions(uid: Int, page: Int) async throws -> [UserDiscussionRecord] {
        let request = makeRequest(
            path: "/api/content/list-discussions",
            queryItems: [
                URLQueryItem(name: "uid", value: "\(uid)"),
                URLQueryItem(name: "page", value: "\(max(1, page))")
            ],
            refererUID: uid
        )
        let root = try await fetchJSON(from: request)
        let rows = try Self.requireRows(in: root, preferredNames: ["discussions", "postList", "list", "data"])
        return rows.compactMap { row in
            guard let title = Self.string(row, ["title", "post_title", "subject"]),
                  let postID = Self.int(row, ["post_id", "postId", "pid", "id"]) else { return nil }
            return UserDiscussionRecord(
                rank: Self.int(row, ["rank"]) ?? 0,
                title: title,
                postID: postID,
                authorName: Self.string(row, ["author_name", "member_name", "username", "user_name", "author", "commenter_name", "name"]),
                level: Self.int(row, ["level", "member_level"]),
                avatarURL: Self.string(row, ["avatar", "avatar_url", "avatar_path"]).flatMap {
                    URL(string: $0, relativeTo: self.baseURL)?.absoluteURL
                },
                viewCount: Self.int(row, ["view_count", "views", "click", "nView", "view_num", "click_count"]),
                replyCount: Self.int(row, ["reply_count", "comments", "comment_count", "nComment", "n_reply", "reply", "comment_num", "reply_num"]),
                createdAtText: Self.string(row, ["created_at_str", "created_at", "createdAt", "post_time", "time", "date"]),
                lastActivityText: Self.string(row, ["last_reply_time", "last_reply_time_str", "last_activity", "last_activity_str", "updated_at", "last_comment_time"])
            )
        }
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem], refererUID: Int) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems
        let url = components?.url ?? baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        let referer = baseURL
            .appendingPathComponent("space")
            .appendingPathComponent("\(refererUID)")
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: referer)
        return request
    }

    private func fetchJSON(from request: URLRequest) async throws -> [String: Any] {
        let (data, urlResponse) = try await session.data(for: request)
        if let httpResponse = urlResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw UserContentClientError.httpStatus(httpResponse.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UserContentClientError.unsuccessfulResponse
        }
        if let success = object["success"] as? Bool, success == false {
            throw UserContentClientError.unsuccessfulResponse
        }
        return object
    }

    private static func requireRows(in root: [String: Any], preferredNames: [String]) throws -> [[String: Any]] {
        if let rows = rows(in: root, preferredNames: preferredNames) {
            return rows
        }
        throw UserContentClientError.unsuccessfulResponse
    }

    private static func rows(in root: [String: Any], preferredNames: [String]) -> [[String: Any]]? {
        for name in preferredNames {
            if let value = root[name] as? [[String: Any]] { return value }
        }
        for name in preferredNames {
            for value in root.values {
                guard let nested = value as? [String: Any] else { continue }
                if let rows = nested[name] as? [[String: Any]] { return rows }
            }
        }
        let candidates = collectObjectArrays(in: root)
        if candidates.count == 1 { return candidates[0] }
        if !candidates.isEmpty, candidates.allSatisfy({ $0.isEmpty }) { return candidates[0] }
        return nil
    }

    private static func collectObjectArrays(in value: Any) -> [[String: Any]] {
        if let array = value as? [[String: Any]] { return [array] }
        if let object = value as? [String: Any] {
            return object.values.flatMap { collectObjectArrays(in: $0) }
        }
        return []
    }

    private static func string(_ object: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            guard let raw = object[key] as? String else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false, trimmed != "null" { return trimmed }
        }
        return nil
    }

    private static func int(_ object: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let number = object[key] as? NSNumber, number.intValue >= 0 {
                return number.intValue
            }
            if let raw = object[key] as? String,
               let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
               value >= 0 {
                return value
            }
        }
        return nil
    }
}

enum UserContentClientError: LocalizedError {
    case httpStatus(Int)
    case unsuccessfulResponse

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessfulResponse:
            return "接口返回失败"
        }
    }
}