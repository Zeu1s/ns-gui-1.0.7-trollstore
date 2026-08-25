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
    var content: String?
    var resolvedCommentPage: Int?
    let unreadCount: Int?

    var isViewed: Bool {
        viewed != 0
    }

    var commentPage: Int {
        max(1, (floorID + 9) / 10)
    }

    var targetCommentPage: Int {
        resolvedCommentPage ?? commentPage
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
        case replyContent = "reply_content"
        case commentText = "comment_text"
        case contentHTML = "content_html"
        case html
        case body
        case bodyHTML = "body_html"
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
        content = Self.optionalString(
            in: container,
            keys: [.content, .commentContent, .replyContent, .commentText, .contentHTML, .html, .body, .bodyHTML, .excerpt, .message]
        )
        resolvedCommentPage = nil
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
        resolvedCommentPage: Int? = nil,
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
        self.resolvedCommentPage = resolvedCommentPage
        self.unreadCount = unreadCount
    }
}

protocol NodeSeekNotificationContentResolving: Sendable {
    func resolveContent(
        for record: NodeSeekNotificationRecord
    ) async -> NodeSeekNotificationContentResolver.ResolvedContent?
}

/// 通知接口不带回帖正文。这里不再用固定的每页评论数猜页码：先读取第 2 页，
/// 通过真实楼层起点确定当前站点分页，再精确读取目标评论所在页。
actor NodeSeekNotificationContentResolver {
    static let shared = NodeSeekNotificationContentResolver()

    private enum DetailRequestLimit {
        // 通知正文只是辅助信息，不能与用户正在浏览的帖子争抢请求和 WebView 资源。
        static let maximumConcurrentRequests = 1
        static let minimumRequestInterval: TimeInterval = 1.2
        static let failedRequestRetryInterval: TimeInterval = 600
        static let maximumCachedDetails = 40

    }

    // 与首页、帖子详情复用 HTTP 优先策略，避免通知补拉全部排队等待单一隐藏 WebView。
    @MainActor private static let detailService = NodeSeekService(
        htmlClient: HTMLLoadingStrategyFactory.makeDefaultClient()
    )

    private var cachedDetails: [String: PostDetail] = [:]
    private var cachedDetailKeys: [String] = []
    private var inFlightDetails: [String: Task<PostDetail?, Never>] = [:]
    private var activeDetailRequestCount = 0
    private var detailRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastDetailRequestStartDate: Date?
    private var failedDetailRetryDates: [String: Date] = [:]


    struct ResolvedContent: Sendable {
        let content: String
        let page: Int
    }

    func resolveContent(for record: NodeSeekNotificationRecord) async -> ResolvedContent? {
        guard record.postID > 0 else { return nil }

        // 前十楼固定在首屏，不需要额外探测。
        if record.floorID <= 10,
           let detail = await detail(postID: record.postID, page: 1),
           let content = Self.content(in: detail, for: record) {
            return ResolvedContent(content: content, page: 1)
        }

        // 网站会根据当前配置改变评论分页数。第 2 页的首个真实楼层即为每页评论数加 1。
        guard let probeDetail = await detail(postID: record.postID, page: 2) else {
            return nil
        }
        if let content = Self.content(in: probeDetail, for: record) {
            return ResolvedContent(content: content, page: 2)
        }
        guard let commentsPerPage = Self.commentsPerPage(inSecondPage: probeDetail) else {
            return nil
        }

        let targetPage = Self.page(for: record.floorID, commentsPerPage: commentsPerPage)
        guard targetPage != 2,
              let detail = await detail(postID: record.postID, page: targetPage),
              let content = Self.content(in: detail, for: record) else {
            return nil
        }
        return ResolvedContent(content: content, page: targetPage)
    }

    private func detail(postID: Int, page: Int) async -> PostDetail? {
        let key = "\(postID)-\(page)"
        if let cached = cachedDetails[key] {
            return cached
        }
        if let retryDate = failedDetailRetryDates[key] {
            if retryDate > Date() {
                return nil
            }
            failedDetailRetryDates[key] = nil
        }
        if let request = inFlightDetails[key] {
            return await request.value
        }

        // 先登记 in-flight，再切到 MainActor 获取共享 service。否则 actor 在 await
        // 期间会重入，相同帖子页会被多个补全任务同时重复请求。
        let request = Task { [weak self] () -> PostDetail? in
            guard let self else { return nil }
            let service = await MainActor.run { Self.detailService }
            return await self.loadDetail(
                using: service,
                postID: postID,
                page: page
            )
        }
        inFlightDetails[key] = request
        let resolved = await request.value
        inFlightDetails[key] = nil
        guard Task.isCancelled == false else { return nil }
        if let resolved {
            cachedDetails[key] = resolved
            cachedDetailKeys.append(key)
            while cachedDetails.count > DetailRequestLimit.maximumCachedDetails,
                  let oldestKey = cachedDetailKeys.first {
                cachedDetailKeys.removeFirst()
                cachedDetails.removeValue(forKey: oldestKey)
            }
            failedDetailRetryDates[key] = nil
        } else {
            failedDetailRetryDates[key] = Date().addingTimeInterval(DetailRequestLimit.failedRequestRetryInterval)
        }
        return resolved
    }

    private func loadDetail(
        using service: NodeSeekService,
        postID: Int,
        page: Int
    ) async -> PostDetail? {
        await acquireDetailRequestSlot()
        defer { releaseDetailRequestSlot() }

        guard Task.isCancelled == false else { return nil }
        do {
            let result = try await service.loadPostDetail(postID: "\(postID)", page: page)
            guard case let .value(detail) = result else { return nil }
            return detail
        } catch {
            guard Task.isCancelled == false else { return nil }
            AppLog.warning(.service, "通知回复补全失败，postID=\(postID), page=\(page): \(error.localizedDescription)")
            return nil
        }
    }

    private func acquireDetailRequestSlot() async {
        if activeDetailRequestCount < DetailRequestLimit.maximumConcurrentRequests {
            activeDetailRequestCount += 1
        } else {
            await withCheckedContinuation { continuation in
                detailRequestWaiters.append(continuation)
            }
        }

        if let lastDetailRequestStartDate {
            let elapsed = Date().timeIntervalSince(lastDetailRequestStartDate)
            let delay = DetailRequestLimit.minimumRequestInterval - elapsed
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        lastDetailRequestStartDate = Date()
    }

    private func releaseDetailRequestSlot() {
        if detailRequestWaiters.isEmpty {
            activeDetailRequestCount -= 1
        } else {
            detailRequestWaiters.removeFirst().resume()
        }
    }
    static func content(in detail: PostDetail, for record: NodeSeekNotificationRecord) -> String? {
        if record.commentID > 0,
           let comment = detail.comments.first(where: {
               $0.id == "\(record.commentID)" || Self.numericIdentifier(in: $0.id) == record.commentID
           }) {
            return comment.contentHTML
        }
        if let comment = detail.comments.first(where: { $0.anchorID == record.anchorID }) {
            return comment.contentHTML
        }
        if let comment = detail.comments.first(where: { Self.floorNumber(in: $0.floorText) == record.floorID }) {
            return comment.contentHTML
        }
        return nil
    }

    static func commentsPerPage(inSecondPage detail: PostDetail) -> Int? {
        let floors = detail.comments.compactMap { floorNumber(in: $0.floorText) }
        guard let firstFloor = floors.min(), firstFloor > 10 else { return nil }
        return firstFloor - 1
    }

    static func page(for floor: Int, commentsPerPage: Int) -> Int {
        guard floor > 10 else { return 1 }
        return max(1, ((floor - 1) / max(1, commentsPerPage)) + 1)
    }

    private static func floorNumber(in floorText: String?) -> Int? {
        numericIdentifier(in: floorText)
    }

    private static func numericIdentifier(in value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        return Int(digits)
    }
}

extension NodeSeekNotificationContentResolver: NodeSeekNotificationContentResolving {}

enum NodeSeekNotificationCacheEvent {
    private static let ownerIDKey = "ownerID"

    static func post(ownerID: Int) {
        NotificationCenter.default.post(
            name: .nodeSeekNotificationCacheDidUpdate,
            object: nil,
            userInfo: [ownerIDKey: ownerID]
        )
    }

    static func ownerID(from notification: Notification) -> Int? {
        notification.userInfo?[ownerIDKey] as? Int
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

    private static func optionalFlag(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
                return value ? 1 : 0
            }
            if let raw = try? container.decodeIfPresent(String.self, forKey: key) {
                if let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return value
                }
                if raw.lowercased() == "true" {
                    return 1
                }
                if raw.lowercased() == "false" {
                    return 0
                }
            }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case receiverID = "receiver_id"
        case receiverIDCamel = "receiverId"
        case recipientID = "recipient_id"
        case toID = "to_id"
        case senderID = "sender_id"
        case senderIDCamel = "senderId"
        case fromID = "from_id"
        case maxID = "max_id"
        case maxIDCamel = "maxId"
        case messageID = "message_id"
        case id
        case content
        case messageContent = "message_content"
        case latestContent = "latest_content"
        case message
        case createdAt = "created_at"
        case createdAtCamel = "createdAt"
        case updatedAt = "updated_at"
        case viewed
        case senderName = "sender_name"
        case senderNameCamel = "senderName"
        case fromName = "from_name"
        case receiverName = "receiver_name"
        case receiverNameCamel = "receiverName"
        case recipientName = "recipient_name"
        case toName = "to_name"
        case unread
        case unreadCount = "unread_count"
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        receiverID = Self.optionalInt(in: container, keys: [.receiverID, .receiverIDCamel, .recipientID, .toID]) ?? 0
        senderID = Self.optionalInt(in: container, keys: [.senderID, .senderIDCamel, .fromID]) ?? 0
        maxID = Self.optionalInt(in: container, keys: [.maxID, .maxIDCamel, .messageID, .id]) ?? 0
        content = Self.optionalString(in: container, keys: [.content, .messageContent, .latestContent, .message]) ?? ""
        let createdAtText = Self.optionalString(in: container, keys: [.createdAt, .createdAtCamel, .updatedAt])
        createdAt = createdAtText.flatMap(NodeSeekNotificationDateParser.date(from:)) ?? .distantPast
        viewed = Self.optionalFlag(in: container, keys: [.viewed]) ?? 0
        senderName = Self.optionalString(in: container, keys: [.senderName, .senderNameCamel, .fromName]) ?? ""
        receiverName = Self.optionalString(in: container, keys: [.receiverName, .receiverNameCamel, .recipientName, .toName]) ?? ""
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

    static func latestConversations(
        from records: [NodeSeekMessageConversationRecord],
        currentUserID: Int?
    ) -> [NodeSeekMessageConversationRecord] {
        guard let currentUserID else {
            return records.sorted(by: Self.isNewer)
        }

        var latestByParticipant: [Int: NodeSeekMessageConversationRecord] = [:]
        var ungrouped: [NodeSeekMessageConversationRecord] = []
        for var record in records {
            let participantID = record.participantID(currentUserID: currentUserID)
            guard participantID > 0, participantID != currentUserID else {
                ungrouped.append(record)
                continue
            }
            if record.senderID == currentUserID {
                record.viewed = 1
            }
            guard let current = latestByParticipant[participantID] else {
                latestByParticipant[participantID] = record
                continue
            }
            if Self.isNewer(record, than: current) {
                latestByParticipant[participantID] = record
            }
        }
        return (Array(latestByParticipant.values) + ungrouped).sorted(by: Self.isNewer)
    }

    private static func isNewer(
        _ lhs: NodeSeekMessageConversationRecord,
        than rhs: NodeSeekMessageConversationRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.maxID > rhs.maxID
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
