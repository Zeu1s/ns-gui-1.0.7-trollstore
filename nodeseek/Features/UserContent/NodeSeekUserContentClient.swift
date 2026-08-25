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
            let sources = Self.postSources(in: row)
            let authorSources = Array(sources.reversed())
            let metricSources = Self.metricSources(in: row)
            guard let title = Self.string(sources, ["title", "post_title", "subject"]),
                  let postID = Self.int(sources, ["post_id", "postId", "pid", "id"]) else { return nil }
            return UserCollectionRecord(
                title: title,
                postID: postID,
                rank: Self.int(sources, ["rank"]) ?? 0,
                authorName: Self.string(authorSources, ["author_name", "member_name", "username", "user_name", "author", "commenter_name", "name"]),
                avatarURL: Self.string(authorSources, ["avatar", "avatar_url", "avatar_path"]).flatMap {
                    URL(string: $0, relativeTo: self.baseURL)?.absoluteURL
                },
                viewCount: Self.metricInt(metricSources, ["view_count", "viewCount", "viewNum", "viewNumber", "views", "view", "click", "nView", "n_view", "n_views", "view_num", "click_count", "post_views", "post_view_count"]),
                replyCount: Self.metricInt(metricSources, ["reply_count", "replyCount", "replyNum", "replies", "comments", "comment_count", "commentCount", "commentNum", "nComment", "n_comment", "n_reply", "reply", "comment_num", "reply_num", "post_comments", "post_reply_count"]),
                lastActivityText: Self.string(sources, ["last_reply_time", "last_reply_time_str", "last_activity", "last_activity_str", "updated_at", "last_comment_time"])
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
            let postSources = Self.postSources(in: row)
            let commentSources = Self.commentSources(in: row)
            guard let postID = Self.int(postSources, ["post_id", "postId", "pid", "id"]) else { return nil }
            return UserCommentRecord(
                postID: postID,
                title: Self.string(postSources, ["title", "post_title", "subject"]) ?? "",
                rank: Self.int(commentSources, ["rank"]) ?? 0,
                floorID: Self.int(commentSources, ["floor_id", "floorId", "floor"]) ?? 1,
                text: Self.string(commentSources, ["text", "content", "comment", "body", "excerpt"]) ?? ""
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
            let sources = Self.postSources(in: row)
            let authorSources = Array(sources.reversed())
            let metricSources = Self.metricSources(in: row)
            let latestReplySources = Self.latestReplySources(in: row)
            guard let title = Self.string(sources, ["title", "post_title", "subject"]),
                  let postID = Self.int(sources, ["post_id", "postId", "pid", "id"]) else { return nil }
            return UserDiscussionRecord(
                rank: Self.int(sources, ["rank"]) ?? 0,
                title: title,
                postID: postID,
                authorName: Self.string(authorSources, ["author_name", "member_name", "username", "user_name", "author", "commenter_name", "name"]),
                authorID: Self.int(authorSources, ["author_id", "authorId", "member_id", "memberId", "uid", "user_id", "userId", "creator_id"]),
                level: Self.int(authorSources, ["level", "member_level"]).map { min(6, max(0, $0)) },
                joinDays: Self.int(authorSources, ["join_days", "joinDays", "register_days", "days"]),
                avatarURL: Self.string(authorSources, ["avatar", "avatar_url", "avatar_path"]).flatMap {
                    URL(string: $0, relativeTo: self.baseURL)?.absoluteURL
                },
                viewCount: Self.metricInt(metricSources, ["view_count", "viewCount", "viewNum", "viewNumber", "views", "view", "click", "nView", "n_view", "n_views", "view_num", "click_count", "post_views", "post_view_count"]),
                replyCount: Self.metricInt(metricSources, ["reply_count", "replyCount", "replyNum", "replies", "comments", "comment_count", "commentCount", "commentNum", "nComment", "n_comment", "n_reply", "reply", "comment_num", "reply_num", "post_comments", "post_reply_count"]),
                createdAtText: Self.string(sources, ["created_at_str", "created_at", "createdAt", "post_time", "time", "date"]),
                lastActivityText: Self.string(latestReplySources + sources, ["last_reply_time", "lastReplyTime", "last_reply_time_str", "last_activity", "last_activity_str", "updated_at", "last_comment_time", "lastCommentTime", "created_at", "createdAt"]),
                lastReplyAuthorName: Self.string(latestReplySources + sources, ["last_reply_author", "last_reply_username", "last_reply_name", "last_commenter_name", "last_comment_username", "last_reply_member_name", "member_name", "username", "user_name", "author", "name"]),
                lastReplyAuthorID: Self.int(latestReplySources + sources, ["last_reply_author_id", "last_reply_user_id", "last_reply_member_id", "last_commenter_id", "last_comment_member_id", "member_id", "user_id", "userId", "uid", "id"]),
                nodeName: Self.string(
                    sources,
                    [
                        "node_name", "nodeName", "node_title", "nodeTitle",
                        "board_name", "boardName", "board_title", "boardTitle",
                        "category_name", "categoryName", "category_title", "categoryTitle",
                        "forum_name", "forumName", "forum_title", "forumTitle",
                        "category", "node", "board", "forum"
                    ]
                )
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
        if candidates.count == 1 { return candidates }
        if !candidates.isEmpty, candidates.allSatisfy({ $0.isEmpty }) { return candidates }
        return nil
    }

    private static func collectObjectArrays(in value: Any) -> [[String: Any]] {
        if let array = value as? [[String: Any]] { return array }
        if let object = value as? [String: Any] {
            return object.values.flatMap { collectObjectArrays(in: $0) }
        }
        return []
    }

    private static func postSources(in row: [String: Any]) -> [[String: Any]] {
        let nestedKeys = [
            "post", "post_data", "postData", "topic", "topic_data", "topicData",
            "statistics", "post_statistics", "stat",
            "node_info", "nodeInfo", "category_info", "categoryInfo",
            "board", "board_info", "boardInfo", "forum", "forum_info", "forumInfo",
            "user", "user_info", "userInfo", "member", "member_info", "memberInfo",
            "author_info", "authorInfo", "creator", "poster", "publisher"
        ]
        var sources: [[String: Any]] = []

        func appendSources(from object: [String: Any]) {
            sources.append(object)
            for key in nestedKeys {
                if let nested = object[key] as? [String: Any] {
                    appendSources(from: nested)
                }
            }
        }

        appendSources(from: row)
        return sources
    }

    private static func latestReplySources(in row: [String: Any]) -> [[String: Any]] {
        let replyKeys = [
            "last_reply", "lastReply", "latest_reply", "latestReply",
            "last_comment", "lastComment", "last_reply_user", "lastReplyUser",
            "last_comment_user", "lastCommentUser"
        ]
        let personKeys = [
            "user", "user_info", "userInfo", "member", "member_info", "memberInfo",
            "author", "author_info", "authorInfo"
        ]
        var sources: [[String: Any]] = []

        func appendSources(from object: [String: Any]) {
            sources.append(object)
            for key in personKeys {
                if let nested = object[key] as? [String: Any] {
                    appendSources(from: nested)
                }
            }
        }

        for object in collectNestedObjects(in: row) {
            for key in replyKeys {
                if let nested = object[key] as? [String: Any] {
                    appendSources(from: nested)
                }
            }
        }
        return sources
    }

    private static func commentSources(in row: [String: Any]) -> [[String: Any]] {
        let nestedKeys = [
            "comment", "comment_data", "commentData", "reply", "reply_data", "replyData",
            "content_data", "contentData"
        ]
        var sources: [[String: Any]] = []

        func appendSources(from object: [String: Any]) {
            sources.append(object)
            for key in nestedKeys {
                if let nested = object[key] as? [String: Any] {
                    appendSources(from: nested)
                }
            }
        }

        appendSources(from: row)
        return sources
    }

    /// 接口包装层偶尔会带同名的旧统计值，先读取最内层的 statistics，
    /// 再回退到帖子和外层字段，避免用 0 覆盖真实统计。
    private static func metricSources(in row: [String: Any]) -> [[String: Any]] {
        let nestedKeys = [
            "statistics", "post_statistics", "postStatistics", "stat",
            "post", "post_data", "postData", "topic", "topic_data", "topicData"
        ]
        var sources: [[String: Any]] = []

        func appendSources(from object: [String: Any]) {
            for key in nestedKeys where ["statistics", "post_statistics", "postStatistics", "stat"].contains(key) {
                if let nested = object[key] as? [String: Any] {
                    appendSources(from: nested)
                }
            }
            for key in nestedKeys where ["post", "post_data", "postData", "topic", "topic_data", "topicData"].contains(key) {
                if let nested = object[key] as? [String: Any] {
                    appendSources(from: nested)
                }
            }
            sources.append(object)
        }

        appendSources(from: row)
        // 接口会随版本在 data/payload/metrics 等包装层中调整字段位置。
        // 已知帖子结构保持优先级，随后补充其余对象，既不遗漏真实统计，
        // 也不会让最外层的 0 覆盖深层的实际数值。
        sources.append(contentsOf: collectNestedObjects(in: row))
        return sources
    }

    private static func collectNestedObjects(in value: Any) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            return [object] + object.values.flatMap(collectNestedObjects(in:))
        }
        if let objects = value as? [Any] {
            return objects.flatMap(collectNestedObjects(in:))
        }
        return []
    }

    private static func string(_ sources: [[String: Any]], _ keys: [String]) -> String? {
        for object in sources {
            for key in keys {
                guard let raw = object[key] as? String else { continue }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false, trimmed != "null" { return trimmed }
            }
        }
        return nil
    }

    private static func string(_ object: [String: Any], _ keys: [String]) -> String? {
        string([object], keys)
    }

    private static func int(_ sources: [[String: Any]], _ keys: [String]) -> Int? {
        for object in sources {
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
        }
        return nil
    }

    private static func int(_ object: [String: Any], _ keys: [String]) -> Int? {
        int([object], keys)
    }

    private static func metricInt(_ sources: [[String: Any]], _ keys: [String]) -> Int? {
        var fallbackZero: Int?
        for object in sources {
            for key in keys {
                guard let value = metricValue(object[key]) else { continue }
                if value > 0 { return value }
                fallbackZero = value
            }
        }
        return fallbackZero
    }

    private static func metricValue(_ raw: Any?) -> Int? {
        if let number = raw as? NSNumber, number.intValue >= 0 {
            return number.intValue
        }
        guard let value = raw as? String else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        if let integer = Int(normalized), integer >= 0 {
            return integer
        }
        let lowercased = normalized.lowercased()
        let multiplier: Double
        let numberText: String
        if lowercased.hasSuffix("k") {
            multiplier = 1_000
            numberText = String(lowercased.dropLast())
        } else if lowercased.hasSuffix("m") {
            multiplier = 1_000_000
            numberText = String(lowercased.dropLast())
        } else if normalized.hasSuffix("万") {
            multiplier = 10_000
            numberText = String(normalized.dropLast())
        } else {
            return nil
        }
        guard let number = Double(numberText), number >= 0 else { return nil }
        return Int((number * multiplier).rounded())
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
