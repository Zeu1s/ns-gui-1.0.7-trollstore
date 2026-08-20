//
//  NodeSeekNotificationRecords.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import Foundation

nonisolated enum NodeSeekNotificationTab: Int, CaseIterable, Hashable, Sendable {
    case atMe
    case reply
    case message

    var title: String {
        switch self {
        case .atMe:
            return "@我"
        case .reply:
            return "回复主题"
        case .message:
            return "私信"
        }
    }

    var webURL: URL {
        switch self {
        case .atMe:
            return NodeSeekNotificationURLBuilder.webURL(fragment: "/atMe")
        case .reply:
            return NodeSeekNotificationURLBuilder.webURL(fragment: "/reply")
        case .message:
            return NodeSeekNotificationURLBuilder.webURL(fragment: "/message?mode=list")
        }
    }
}

nonisolated struct NodeSeekNotificationUnreadCount: Equatable, Sendable {
    var message: Int
    var atMe: Int
    var reply: Int
    var all: Int

    static let zero = NodeSeekNotificationUnreadCount(message: 0, atMe: 0, reply: 0, all: 0)

    func count(for tab: NodeSeekNotificationTab) -> Int {
        switch tab {
        case .atMe:
            return atMe
        case .reply:
            return reply
        case .message:
            return message
        }
    }

    mutating func setCount(_ count: Int, for tab: NodeSeekNotificationTab) {
        let normalized = max(0, count)
        switch tab {
        case .atMe:
            atMe = normalized
        case .reply:
            reply = normalized
        case .message:
            message = normalized
        }
        all = atMe + reply + message
    }

    mutating func decrement(for tab: NodeSeekNotificationTab, by amount: Int = 1) {
        setCount(count(for: tab) - max(0, amount), for: tab)
    }
}

enum NodeSeekNotificationUnreadCountEvent {
    private static let unreadCountKey = "unreadCount"

    static func post(_ unreadCount: NodeSeekNotificationUnreadCount) {
        NotificationCenter.default.post(
            name: .nodeSeekNotificationUnreadCountDidUpdate,
            object: nil,
            userInfo: [unreadCountKey: unreadCount]
        )
    }

    static func unreadCount(from notification: Notification) -> NodeSeekNotificationUnreadCount? {
        notification.userInfo?[unreadCountKey] as? NodeSeekNotificationUnreadCount
    }
}

nonisolated struct NodeSeekNotificationRecord: Decodable, Equatable, Sendable {
    let id: Int
    var viewed: Int
    let commentID: Int
    let floorID: Int
    let createdAt: Date
    let commenterID: Int
    let title: String
    let postID: Int
    let firstCommentID: Int
    let commenterName: String
    let content: String?
    let unreadCount: Int?

    var isViewed: Bool {
        viewed != 0
    }

    var commentPage: Int {
        max(1, (floorID + 9) / 10)
    }

    var anchorID: String {
        "\(floorID)"
    }

    var avatarURL: URL {
        NodeSeekNotificationURLBuilder.avatarURL(memberID: commenterID)
    }

    var profileURL: URL {
        NodeSeekNotificationURLBuilder.profileURL(memberID: commenterID)
    }

    var postSummary: PostSummary {
        UserContentPostSummaryFactory.postSummary(id: postID, title: title)
    }

    /// 单条通知的未读数量：接口未返回时以已读状态推断。
    var displayUnreadCount: Int {
        unreadCount ?? (isViewed ? 0 : 1)
    }

    mutating func markViewed() {
        viewed = 1
    }

    private static func optionalString(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key),
               value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return value
            }
        }
        return nil
    }

    private static func optionalInt(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key), value > 0 {
                return value
            }
            if let raw = try? container.decodeIfPresent(String.self, forKey: key),
               let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 {
                return value
            }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case viewed
        case commentID = "comment_id"
        case replyID = "reply_id"
        case floorID = "floor_id"
        case floor
        case floorIDCamel = "floorId"
        case createdAt = "created_at"
        case commenterID = "commenter_id"
        case memberID = "member_id"
        case senderID = "sender_id"
        case uid
        case title
        case postTitle = "post_title"
        case discussionTitle = "discussion_title"
        case postID = "post_id"
        case postIDCamel = "postId"
        case discussionID = "discussion_id"
        case firstCommentID = "first_comment_id"
        case commenterName = "commenter_name"
        case username
        case senderName = "sender_name"
        case name
        case content
        case commentContent = "comment_content"
        case excerpt
        case message
        case unread
        case unreadCount = "unread_count"
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        viewed = try container.decode(Int.self, forKey: .viewed)
        commentID = Self.optionalInt(in: container, keys: [.commentID, .replyID]) ?? 0
        floorID = Self.optionalInt(in: container, keys: [.floorID, .floor, .floorIDCamel]) ?? 1
        let createdAtText = try container.decode(String.self, forKey: .createdAt)
        guard let parsedDate = NodeSeekNotificationDateParser.date(from: createdAtText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Invalid notification date: \(createdAtText)"
            )
        }
        createdAt = parsedDate
        commenterID = Self.optionalInt(in: container, keys: [.commenterID, .memberID, .senderID, .uid]) ?? 0
        title = Self.optionalString(in: container, keys: [.title, .postTitle, .discussionTitle]) ?? ""
        postID = Self.optionalInt(in: container, keys: [.postID, .postIDCamel, .discussionID]) ?? 0
        firstCommentID = Self.optionalInt(in: container, keys: [.firstCommentID]) ?? 0
        commenterName = Self.optionalString(in: container, keys: [.commenterName, .username, .senderName, .name]) ?? ""
        content = Self.optionalString(in: container, keys: [.content, .commentContent, .excerpt, .message])
        unreadCount = Self.optionalInt(in: container, keys: [.unread, .unreadCount, .count])
    }

    init(
        id: Int,
        viewed: Int,
        commentID: Int,
        floorID: Int,
        createdAt: Date,
        commenterID: Int,
        title: String,
        postID: Int,
        firstCommentID: Int,
        content: String? = nil,
        unreadCount: Int? = nil,
        commenterName: String
    ) {
        self.id = id
        self.viewed = viewed
        self.commentID = commentID
        self.floorID = floorID
        self.createdAt = createdAt
        self.commenterID = commenterID
        self.title = title
        self.postID = postID
        self.firstCommentID = firstCommentID
        self.commenterName = commenterName
        self.content = content
        self.unreadCount = unreadCount
    }
}

nonisolated struct NodeSeekMessageConversationRecord: Decodable, Equatable, Sendable {
    let receiverID: Int
    let senderID: Int
    let maxID: Int
    let content: String
    let createdAt: Date
    var viewed: Int
    let senderName: String
    let unreadCount: Int?
    let receiverName: String

    /// 单条私信会话的未读数量：接口未返回时以已读状态推断。
    var displayUnreadCount: Int {
        unreadCount ?? (isViewed ? 0 : 1)
    }

    var isViewed: Bool {
        viewed != 0
    }

    func participantID(currentUserID: Int?) -> Int {
        guard let currentUserID else { return senderID }
        return senderID == currentUserID ? receiverID : senderID
    }

    func participantName(currentUserID: Int?) -> String {
        guard let currentUserID else { return senderName }
        return senderID == currentUserID ? receiverName : senderName
    }

    func participantAvatarURL(currentUserID: Int?) -> URL {
        NodeSeekNotificationURLBuilder.avatarURL(memberID: participantID(currentUserID: currentUserID))
    }

    func participantProfileURL(currentUserID: Int?) -> URL {
        NodeSeekNotificationURLBuilder.profileURL(memberID: participantID(currentUserID: currentUserID))
    }

    func conversationWebURL(currentUserID: Int?) -> URL {
        NodeSeekNotificationURLBuilder.webURL(
            fragment: "/message?mode=talk&to=\(participantID(currentUserID: currentUserID))"
        )
    }

    mutating func markViewed() {
        viewed = 1
    }

    private static func optionalInt(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key), value > 0 {
                return value
            }
            if let raw = try? container.decodeIfPresent(String.self, forKey: key),
               let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 {
                return value
            }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case receiverID = "receiver_id"
        case senderID = "sender_id"
        case maxID = "max_id"
        case content
        case createdAt = "created_at"
        case viewed
        case senderName = "sender_name"
        case receiverName = "receiver_name"
        case unread
        case unreadCount = "unread_count"
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        receiverID = try container.decode(Int.self, forKey: .receiverID)
        senderID = try container.decode(Int.self, forKey: .senderID)
        maxID = try container.decode(Int.self, forKey: .maxID)
        content = try container.decode(String.self, forKey: .content)
        let createdAtText = try container.decode(String.self, forKey: .createdAt)
        guard let parsedDate = NodeSeekNotificationDateParser.date(from: createdAtText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Invalid message date: \(createdAtText)"
            )
        }
        createdAt = parsedDate
        viewed = try container.decode(Int.self, forKey: .viewed)
        senderName = try container.decode(String.self, forKey: .senderName)
        receiverName = try container.decode(String.self, forKey: .receiverName)
        unreadCount = Self.optionalInt(in: container, keys: [.unread, .unreadCount, .count])
    }

    init(
        receiverID: Int,
        senderID: Int,
        maxID: Int,
        content: String,
        createdAt: Date,
        viewed: Int,
        senderName: String,
        receiverName: String,
        unreadCount: Int? = nil
    ) {
        self.receiverID = receiverID
        self.senderID = senderID
        self.maxID = maxID
        self.content = content
        self.createdAt = createdAt
        self.viewed = viewed
        self.senderName = senderName
        self.receiverName = receiverName
        self.unreadCount = unreadCount
    }
}

enum NodeSeekNotificationURLBuilder {
    nonisolated static func webURL(fragment: String) -> URL {
        var components = URLComponents(url: NodeSeekSite.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/notification"
        components?.fragment = fragment
        return components?.url ?? NodeSeekSite.baseURL.appendingPathComponent("notification")
    }

    nonisolated static func avatarURL(memberID: Int) -> URL {
        NodeSeekSite.baseURL
            .appendingPathComponent("avatar")
            .appendingPathComponent("\(memberID).png")
    }

    nonisolated static func profileURL(memberID: Int) -> URL {
        NodeSeekSite.baseURL
            .appendingPathComponent("space")
            .appendingPathComponent("\(memberID)")
    }
}

enum NodeSeekNotificationDateParser {
    nonisolated static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    nonisolated static func displayText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/M/d HH:mm:ss"
        return formatter.string(from: date)
    }
}
