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
    /// 与星辰账簿客户端同一模式：请求前先做 cookie 准备。
    /// 站点需要登录的接口在游客态统一返回 500 + "USER NOT FOUND"，
    /// 此前这个客户端完全没同步，收藏/我的评论因此恒定失败。
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

    func loadCollections(page: Int, uid: Int) async throws -> [UserCollectionRecord] {
        let request = makeRequest(
            path: "/api/statistics/list-collection",
            queryItems: [URLQueryItem(name: "page", value: "\(max(1, page))")],
            refererUID: uid
        )
        let root = try await fetchJSON(from: request)
        let rows = try Self.requireRows(in: root, preferredNames: ["collections", "collectionList", "list", "data"])
        Self.logFirstRowKeys("收藏", rows)
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
        Self.logFirstRowKeys("主题帖评论", rows)
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
        Self.logFirstRowKeys("主题帖", rows)
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
        let target = request.url?.absoluteString ?? "nil"
        await cookiePreparer()
        // 诊断：把"请求到底带上了哪几个 cookie"记下来。收藏与通知的 500 是
        // 同一类问题，先确认 session 在不在，再决定是修同步还是修请求头。
        let attachedCookies = HTTPCookieStorage.shared.cookies(for: request.url ?? baseURL)?
            .map(\.name) ?? []
        AppLog.info(
            .service,
            "用户内容接口请求开始 url=\(target) 已附带cookie=\(attachedCookies.joined(separator: ","))"
        )

        let (data, urlResponse) = try await session.data(for: request)
        if let httpResponse = urlResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            let body = String(decoding: data.prefix(240), as: UTF8.self)
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            AppLog.warning(
                .service,
                "用户内容接口响应异常 url=\(target) status=\(httpResponse.statusCode) bytes=\(data.count) body=\(body)"
            )
            // 站点用 500 + "USER NOT FOUND" 表示没有登录态，直译成 HTTP 500
            // 用户完全无法应对；这里翻成可操作的提示。
            if body.contains("USER NOT FOUND") {
                throw UserContentClientError.sessionExpired
            }
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

    /// 诊断：这些列表要不要逐帖抓详情，取决于接口本身给不给统计/板块名。
    /// 解码器是在一大串候选键名里猜，所以先把首行真实键名连同一层嵌套打出来，
    /// 一份日志就能定死是"改解码"还是"必须抓详情"。
    private static func logFirstRowKeys(_ label: String, _ rows: [[String: Any]]) {
        guard let first = rows.first else { return }
        var names = first.keys.sorted()
        for value in first.values {
            if let nested = value as? [String: Any] {
                names += nested.keys.sorted().map { ".\($0)" }
            }
        }
        AppLog.info(.service, "\(label)接口首行键名=\(names.joined(separator: ","))")
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
        // 这里原来还会把 collectNestedObjects 扫出的**每一个**嵌套对象都追加进来。
        // 候选键名里有 views / comments / reply 这类通用词，于是行内任何一个
        // 无关子对象（用户信息、图片列表、徽章数组…）只要带同名键就会被当成统计值，
        // 这是收藏与主题帖浏览数/评论数对不上的直接来源。
        // 宁可少显示一个数字，也不要显示一个错的。
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
    /// 站点在没有登录态时返回 500 + "USER NOT FOUND"，直译成 HTTP 500 用户无从应对。
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessfulResponse:
            return "接口返回失败"
        case .sessionExpired:
            return "登录态已失效，请在设置里重新登录 NodeSeek"
        }
    }
}
