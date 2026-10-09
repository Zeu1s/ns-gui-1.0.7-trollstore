//
//  NodeSeekNotificationMemoryCache.swift
//  nodeseek
//

import Foundation

private final class NodeSeekNotificationDiskCache {
    struct Snapshot {
        let atMeRecords: [NodeSeekNotificationRecord]?
        let replyRecords: [NodeSeekNotificationRecord]?
        let messageRecords: [NodeSeekMessageConversationRecord]?
    }

    private struct StoredSnapshot: Codable {
        var savedAt: Date
        var atMeRecords: [StoredRecord]?
        var replyRecords: [StoredRecord]?
        var messageRecords: [StoredMessageRecord]?
    }

    private struct StoredRecord: Codable {
        let id: Int
        let viewed: Int
        let commentID: Int
        let floorID: Int
        let createdAt: TimeInterval
        let commenterID: Int
        let title: String
        let postID: Int
        let firstCommentID: Int
        let commenterName: String
        let content: String?
        let resolvedCommentPage: Int?
        let unreadCount: Int?

        init(record: NodeSeekNotificationRecord) {
            id = record.id
            viewed = record.viewed
            commentID = record.commentID
            floorID = record.floorID
            createdAt = record.createdAt.timeIntervalSince1970
            commenterID = record.commenterID
            title = record.title
            postID = record.postID
            firstCommentID = record.firstCommentID
            commenterName = record.commenterName
            content = record.content
            resolvedCommentPage = record.resolvedCommentPage
            unreadCount = record.unreadCount
        }

        var notificationRecord: NodeSeekNotificationRecord {
            NodeSeekNotificationRecord(
                id: id,
                viewed: viewed,
                commentID: commentID,
                floorID: floorID,
                createdAt: Date(timeIntervalSince1970: createdAt),
                commenterID: commenterID,
                title: title,
                postID: postID,
                firstCommentID: firstCommentID,
                content: content,
                resolvedCommentPage: resolvedCommentPage,
                unreadCount: unreadCount,
                commenterName: commenterName
            )
        }
    }

    private struct StoredMessageRecord: Codable {
        let receiverID: Int
        let senderID: Int
        let maxID: Int
        let content: String
        let createdAt: TimeInterval
        let viewed: Int
        let senderName: String
        let unreadCount: Int?
        let receiverName: String

        init(record: NodeSeekMessageConversationRecord) {
            receiverID = record.receiverID
            senderID = record.senderID
            maxID = record.maxID
            content = record.content
            createdAt = record.createdAt.timeIntervalSince1970
            viewed = record.viewed
            senderName = record.senderName
            unreadCount = record.unreadCount
            receiverName = record.receiverName
        }

        var conversationRecord: NodeSeekMessageConversationRecord {
            NodeSeekMessageConversationRecord(
                receiverID: receiverID,
                senderID: senderID,
                maxID: maxID,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAt),
                viewed: viewed,
                senderName: senderName,
                receiverName: receiverName,
                unreadCount: unreadCount
            )
        }
    }

    private let defaults: UserDefaults
    private let keyPrefix = "com.nodeseek.notification.content-cache.v1"
    private let maximumAge: TimeInterval = 86_400
    private let maximumRecordsPerTab = 100

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func snapshot(for ownerID: Int) -> Snapshot? {
        guard let stored = decodedSnapshot(for: ownerID) else { return nil }
        guard Date().timeIntervalSince(stored.savedAt) <= maximumAge else {
            defaults.removeObject(forKey: key(for: ownerID))
            return nil
        }
        return Snapshot(
            atMeRecords: stored.atMeRecords?.map(\.notificationRecord),
            replyRecords: stored.replyRecords?.map(\.notificationRecord),
            messageRecords: stored.messageRecords?.map(\.conversationRecord)
        )
    }

    func store(records: [NodeSeekNotificationRecord], for tab: NodeSeekNotificationTab, ownerID: Int) {
        guard tab == .atMe || tab == .reply else { return }
        var snapshot = decodedSnapshot(for: ownerID)
        if let cachedSnapshot = snapshot, Date().timeIntervalSince(cachedSnapshot.savedAt) > maximumAge {
            defaults.removeObject(forKey: key(for: ownerID))
            snapshot = nil
        }
        var stored = snapshot ?? StoredSnapshot(savedAt: Date(), atMeRecords: nil, replyRecords: nil)
        let values = Array(records.prefix(maximumRecordsPerTab)).map(StoredRecord.init(record:))
        switch tab {
        case .atMe:
            stored.atMeRecords = values
        case .reply:
            stored.replyRecords = values
        case .message:
            return
        }
        stored.savedAt = Date()
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key(for: ownerID))
    }

    /// 消息会话也持久化：已读状态参与未读数 reconcile，避免启动初期
    /// 服务器陈旧的 message 计数先上角标、列表落地后又消失的闪现。
    func store(messageRecords: [NodeSeekMessageConversationRecord], ownerID: Int) {
        var snapshot = decodedSnapshot(for: ownerID)
        if let cachedSnapshot = snapshot, Date().timeIntervalSince(cachedSnapshot.savedAt) > maximumAge {
            defaults.removeObject(forKey: key(for: ownerID))
            snapshot = nil
        }
        var stored = snapshot ?? StoredSnapshot(savedAt: Date(), atMeRecords: nil, replyRecords: nil)
        stored.messageRecords = Array(messageRecords.prefix(maximumRecordsPerTab)).map(StoredMessageRecord.init(record:))
        stored.savedAt = Date()
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key(for: ownerID))
    }

    private func decodedSnapshot(for ownerID: Int) -> StoredSnapshot? {
        guard let data = defaults.data(forKey: key(for: ownerID)) else { return nil }
        return try? JSONDecoder().decode(StoredSnapshot.self, from: data)
    }

    /// 一次性写入三份列表。
    ///
    /// 每次 `store` 都要把整份 snapshot decode 出来再 encode 回去；通知页落盘
    /// （`cacheCurrentNotificationData`）会连着写三份列表，逐份写就是三轮
    /// decode + encode 往返。批量写入只做一轮。
    func store(
        atMeRecords: [NodeSeekNotificationRecord]?,
        replyRecords: [NodeSeekNotificationRecord]?,
        messageRecords: [NodeSeekMessageConversationRecord]?,
        ownerID: Int
    ) {
        var snapshot = decodedSnapshot(for: ownerID)
        if let cachedSnapshot = snapshot, Date().timeIntervalSince(cachedSnapshot.savedAt) > maximumAge {
            defaults.removeObject(forKey: key(for: ownerID))
            snapshot = nil
        }
        var stored = snapshot ?? StoredSnapshot(savedAt: Date(), atMeRecords: nil, replyRecords: nil)
        if let atMeRecords {
            stored.atMeRecords = Array(atMeRecords.prefix(maximumRecordsPerTab)).map(StoredRecord.init(record:))
        }
        if let replyRecords {
            stored.replyRecords = Array(replyRecords.prefix(maximumRecordsPerTab)).map(StoredRecord.init(record:))
        }
        if let messageRecords {
            stored.messageRecords = Array(messageRecords.prefix(maximumRecordsPerTab))
                .map(StoredMessageRecord.init(record:))
        }
        stored.savedAt = Date()
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key(for: ownerID))
    }

    private func key(for ownerID: Int) -> String {
        "\(keyPrefix).\(ownerID)"
    }
}
@MainActor
final class NodeSeekNotificationMemoryCache {
    static let shared = NodeSeekNotificationMemoryCache()

    struct Snapshot {
        let atMeRecords: [NodeSeekNotificationRecord]?
        let replyRecords: [NodeSeekNotificationRecord]?
        let messageRecords: [NodeSeekMessageConversationRecord]?
        let unreadCount: NodeSeekNotificationUnreadCount?
    }

    private let persistentCache: NodeSeekNotificationDiskCache
    private var ownerID: Int?
    private var atMeRecords: [NodeSeekNotificationRecord]?
    private var replyRecords: [NodeSeekNotificationRecord]?
    private var messageRecords: [NodeSeekMessageConversationRecord]?
    private var unreadCount: NodeSeekNotificationUnreadCount?

    init(defaults: UserDefaults = .standard) {
        persistentCache = NodeSeekNotificationDiskCache(defaults: defaults)
    }

    func snapshot(for ownerID: Int?) -> Snapshot? {
        guard prepare(for: ownerID) else { return nil }
        return Snapshot(
            atMeRecords: atMeRecords,
            replyRecords: replyRecords,
            messageRecords: messageRecords,
            unreadCount: unreadCount
        )
    }

    func store(
        records: [NodeSeekNotificationRecord],
        for tab: NodeSeekNotificationTab,
        ownerID: Int?
    ) {
        guard prepare(for: ownerID) else { return }
        let resolvedRecords = NodeSeekNotificationReadStateStore.shared.applyingLocalReadState(
            to: records,
            tab: tab,
            ownerID: ownerID
        )
        switch tab {
        case .atMe:
            atMeRecords = resolvedRecords
        case .reply:
            replyRecords = resolvedRecords
        case .message:
            return
        }
        guard let ownerID else { return }
        persistentCache.store(records: resolvedRecords, for: tab, ownerID: ownerID)
    }

    func store(
        messageRecords: [NodeSeekMessageConversationRecord],
        ownerID: Int?
    ) {
        guard prepare(for: ownerID) else { return }
        self.messageRecords = NodeSeekNotificationReadStateStore.shared.applyingLocalReadState(
            to: messageRecords,
            ownerID: ownerID
        )
        guard let ownerID else { return }
        persistentCache.store(messageRecords: self.messageRecords ?? [], ownerID: ownerID)
    }

    /// 通知页落盘走这个入口：三份列表一次写入，磁盘只做一轮 decode + encode。
    ///
    /// 语义与逐份 `store` 完全一致（每份都先过本地已读账本），只是把落盘合并。
    /// 传 nil 表示该标签页未加载、不参与本次写入。
    func storeAll(
        atMeRecords: [NodeSeekNotificationRecord]?,
        replyRecords: [NodeSeekNotificationRecord]?,
        messageRecords: [NodeSeekMessageConversationRecord]?,
        ownerID: Int?
    ) {
        guard prepare(for: ownerID) else { return }
        let readStateStore = NodeSeekNotificationReadStateStore.shared
        if let atMeRecords {
            self.atMeRecords = readStateStore.applyingLocalReadState(
                to: atMeRecords,
                tab: .atMe,
                ownerID: ownerID
            )
        }
        if let replyRecords {
            self.replyRecords = readStateStore.applyingLocalReadState(
                to: replyRecords,
                tab: .reply,
                ownerID: ownerID
            )
        }
        if let messageRecords {
            self.messageRecords = readStateStore.applyingLocalReadState(
                to: messageRecords,
                ownerID: ownerID
            )
        }
        guard let ownerID else { return }
        persistentCache.store(
            atMeRecords: self.atMeRecords,
            replyRecords: self.replyRecords,
            messageRecords: self.messageRecords,
            ownerID: ownerID
        )
    }

    @discardableResult
    func store(
        unreadCount: NodeSeekNotificationUnreadCount,
        ownerID: Int?
    ) -> NodeSeekNotificationUnreadCount? {
        guard prepare(for: ownerID) else { return nil }
        let reconciledCount = reconciledUnreadCount(unreadCount)
        self.unreadCount = reconciledCount
        return reconciledCount
    }

    /// 本地记录只用来**压低**服务器计数，绝不允许抬高。
    ///
    /// 两个方向都测过了（build 127 真机日志，`角标本地修正` 一行出现 7 次，每次都是
    /// `服务器=all:4,atMe:0,reply:0,message:4 → 本地=all:0`）：
    /// 服务器那个 `message:4` 是滞后的假数字，本地三份列表全是已读。
    ///
    /// 所以这里既不能像最早那样无条件覆盖（陈旧快照能凭空凑出一个更大的数），
    /// 也不能像上一轮那样"只信本次进程拉过的数据"（冷启动没有可信标签页，
    /// 就会先把服务器的假 4 画到角标上，等预取回来才归零 —— 用户看到的
    /// "首开亮一下、稍后归零"就是这么来的）。
    /// 取小同时堵住两头：陈旧快照抬不高，服务器滞后时本地赢，
    /// 而磁盘快照还原出来的记录仍然有效，因为它还原后还过了持久本地已读账本。
    private func reconciledUnreadCount(
        _ remoteCount: NodeSeekNotificationUnreadCount
    ) -> NodeSeekNotificationUnreadCount {
        var reconciled = remoteCount
        applyLocalReadCount(&reconciled, for: .atMe, records: atMeRecords)
        applyLocalReadCount(&reconciled, for: .reply, records: replyRecords)
        applyLocalReadCount(&reconciled, for: .message, records: messageRecords)
        logBadgeCorrection(remote: remoteCount, final: reconciled)
        return reconciled
    }

    private func applyLocalReadCount(
        _ count: inout NodeSeekNotificationUnreadCount,
        for tab: NodeSeekNotificationTab,
        records: [NodeSeekNotificationRecord]?
    ) {
        guard let records else { return }
        let local = records.reduce(0) { $0 + ($1.isViewed ? 0 : $1.displayUnreadCount) }
        count.setCount(min(count.count(for: tab), local), for: tab)
    }

    private func applyLocalReadCount(
        _ count: inout NodeSeekNotificationUnreadCount,
        for tab: NodeSeekNotificationTab,
        records: [NodeSeekMessageConversationRecord]?
    ) {
        guard let records else { return }
        let local = records.reduce(0) { $0 + ($1.isViewed ? 0 : $1.displayUnreadCount) }
        count.setCount(min(count.count(for: tab), local), for: tab)
    }

    /// 只有本地确实改动了数字才记一行，用来判断角标是被谁改的。
    private func logBadgeCorrection(
        remote: NodeSeekNotificationUnreadCount,
        final: NodeSeekNotificationUnreadCount
    ) {
        guard remote != final else { return }
        let localCounts = [
            "atMe:\(localUnreadCount(for: .atMe))",
            "reply:\(localUnreadCount(for: .reply))",
            "message:\(localUnreadCount(for: .message))"
        ].joined(separator: ",")
        AppLog.info(
            .account,
            "角标本地修正: 服务器=all:\(remote.all),atMe:\(remote.atMe),reply:\(remote.reply),"
                + "message:\(remote.message) → 最终=all:\(final.all),atMe:\(final.atMe),"
                + "reply:\(final.reply),message:\(final.message) 本地推算=\(localCounts)"
        )
    }

    /// 只给日志用：没有该标签页的列表数据时返回"无"，那一页就不参与修正。
    private func localUnreadCount(for tab: NodeSeekNotificationTab) -> String {
        switch tab {
        case .atMe:
            return atMeRecords.map { records in
                "\(records.reduce(0) { $0 + ($1.isViewed ? 0 : $1.displayUnreadCount) })"
            } ?? "无"
        case .reply:
            return replyRecords.map { records in
                "\(records.reduce(0) { $0 + ($1.isViewed ? 0 : $1.displayUnreadCount) })"
            } ?? "无"
        case .message:
            return messageRecords.map { records in
                "\(records.reduce(0) { $0 + ($1.isViewed ? 0 : $1.displayUnreadCount) })"
            } ?? "无"
        }
    }

    /// 任何要上角标的计数都先过这里：本地列表用来压低服务器可能滞后的计数
    /// （服务端已读提交是异步 WebView，经常回写慢）。三个发布入口都必须走。
    func badgeReadyUnreadCount(_ remoteCount: NodeSeekNotificationUnreadCount, ownerID: Int?) -> NodeSeekNotificationUnreadCount {
        guard prepare(for: ownerID) else { return remoteCount }
        return reconciledUnreadCount(remoteCount)
    }

    private func prepare(for ownerID: Int?) -> Bool {
        guard let ownerID else { return false }
        if self.ownerID != ownerID {
            self.ownerID = ownerID
            let restoredSnapshot = persistentCache.snapshot(for: ownerID)
            atMeRecords = restoredSnapshot?.atMeRecords.map {
                NodeSeekNotificationReadStateStore.shared.applyingLocalReadState(
                    to: $0,
                    tab: .atMe,
                    ownerID: ownerID
                )
            }
            replyRecords = restoredSnapshot?.replyRecords.map {
                NodeSeekNotificationReadStateStore.shared.applyingLocalReadState(
                    to: $0,
                    tab: .reply,
                    ownerID: ownerID
                )
            }
            messageRecords = restoredSnapshot?.messageRecords.map {
                NodeSeekNotificationReadStateStore.shared.applyingLocalReadState(
                    to: $0,
                    ownerID: ownerID
                )
            }
            unreadCount = nil
        }
        return true
    }
}

/// 服务端标记已读是异步 WebView 提交。短暂延迟期间，不能让下一轮预取把用户已读的
/// 通知重新显示成未读，因此按账号保存已读标识并在所有缓存入口统一应用。
@MainActor
final class NodeSeekNotificationReadStateStore {
    static let shared = NodeSeekNotificationReadStateStore()

    private let defaults: UserDefaults
    private let keyPrefix = "com.nodeseek.notification.local-read"
    private let maximumStoredIdentifiers = 1_200

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func markViewed(ids: [Int], tab: NodeSeekNotificationTab, ownerID: Int?) {
        guard let ownerID else { return }
        var values = identifiers(for: tab, ownerID: ownerID)
        values.formUnion(ids.filter { $0 > 0 })
        save(values, for: tab, ownerID: ownerID)
    }

    func removeViewed(ids: [Int], tab: NodeSeekNotificationTab, ownerID: Int?) {
        guard let ownerID else { return }
        var values = identifiers(for: tab, ownerID: ownerID)
        values.subtract(ids)
        save(values, for: tab, ownerID: ownerID)
    }

    /// 批量合并记录前先取一次已读集合。
    ///
    /// `identifiers(for:ownerID:)` 每次调用都会从 UserDefaults 反序列化整个数组并重建
    /// Set（上限 1200 个 id）。逐条记录地取一次，一页 100 条就是上百次重复重建，
    /// 而这个集合在一次合并内根本不会变。这里暴露一次取集合的入口给调用方复用。
    func viewedIdentifiers(for tab: NodeSeekNotificationTab, ownerID: Int?) -> Set<Int> {
        guard let ownerID else { return [] }
        return identifiers(for: tab, ownerID: ownerID)
    }

    func applyingLocalReadState(
        to records: [NodeSeekNotificationRecord],
        tab: NodeSeekNotificationTab,
        ownerID: Int?
    ) -> [NodeSeekNotificationRecord] {
        guard let ownerID else { return records }
        let viewed = identifiers(for: tab, ownerID: ownerID)
        return records.map { record in
            guard viewed.contains(record.id) else { return record }
            var updated = record
            updated.markViewed()
            return updated
        }
    }

    func applyingLocalReadState(
        to records: [NodeSeekMessageConversationRecord],
        ownerID: Int?
    ) -> [NodeSeekMessageConversationRecord] {
        guard let ownerID else { return records }
        let viewed = identifiers(for: .message, ownerID: ownerID)
        return records.map { record in
            guard viewed.contains(record.maxID) else { return record }
            var updated = record
            updated.markViewed()
            return updated
        }
    }

    private func identifiers(for tab: NodeSeekNotificationTab, ownerID: Int) -> Set<Int> {
        let values = defaults.array(forKey: key(for: tab, ownerID: ownerID)) as? [Int] ?? []
        return Set(values)
    }

    private func save(_ values: Set<Int>, for tab: NodeSeekNotificationTab, ownerID: Int) {
        let trimmed = Array(values.sorted(by: >).prefix(maximumStoredIdentifiers))
        defaults.set(trimmed, forKey: key(for: tab, ownerID: ownerID))
    }

    private func key(for tab: NodeSeekNotificationTab, ownerID: Int) -> String {
        "\(keyPrefix).\(ownerID).\(tab.rawValue)"
    }
}

/// 通知页是懒加载的，不能依赖其控制器生命周期做预取。该服务在 App 前台运行，
/// 先保证 @我 可用，再并发填充回复主题和私信缓存。
@MainActor
final class NodeSeekNotificationPrefetcher {
    static let shared = NodeSeekNotificationPrefetcher()

    // 预取降频：45s -> 90s，减少持续请求量，降低触发 Cloudflare 封禁的概率
    private static let refreshInterval: UInt64 = 90_000_000_000

    private let client: NodeSeekNotificationClientProtocol
    private let currentAccountStore: CurrentAccountStore
    private let contentResolver: any NodeSeekNotificationContentResolving
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshOperationTask: Task<Void, Never>?
    private var refreshOperationToken = 0
    private var hasStartedAfterHomePreviewRequest = false
    private var contentEnrichmentTasks: [NodeSeekNotificationTab: Task<Void, Never>] = [:]
    private var contentEnrichmentTokens: [NodeSeekNotificationTab: Int] = [:]
    private var contentEnrichmentRecordIDs: [NodeSeekNotificationTab: Set<Int>] = [:]

    /// 通知正文补全会继续按需进行，但不能在首页启动时占满网络和 WebView 进程。
    /// 每轮 30 条会连续触发十余次隐藏 WebView 抓取（每帖 ~250KB），曾导致内存峰值崩溃，
    /// 降为 8 条分多轮消化。
    private static let maxConcurrentContentResolutions = 1
    private static let maximumContentEnrichmentRecords = 8

    init(
        client: NodeSeekNotificationClientProtocol = NodeSeekNotificationClient(),
        currentAccountStore: CurrentAccountStore = .shared,
        contentResolver: any NodeSeekNotificationContentResolving = NodeSeekNotificationContentResolver.shared
    ) {
        self.client = client
        self.currentAccountStore = currentAccountStore
        self.contentResolver = contentResolver
    }

    func start() {
        refreshNow()
        guard refreshLoopTask == nil else { return }

        refreshLoopTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: Self.refreshInterval)
                } catch {
                    return
                }
                guard let self, Task.isCancelled == false else { return }
                self.refreshNow()
            }
        }
    }

    /// 首页已发起当前板块首屏请求后才允许预取消息，避免冷启动时两个首屏接口争抢连接。
    func startAfterHomePreviewRequest() {
        hasStartedAfterHomePreviewRequest = true
        start()
    }

    /// 首次启动前不抢占首页；其后的前台恢复则继续已有的消息刷新循环。
    func resumeAfterForegroundActivationIfReady() {
        guard hasStartedAfterHomePreviewRequest else { return }
        start()
    }

    func stop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        refreshOperationToken &+= 1
        refreshOperationTask?.cancel()
        refreshOperationTask = nil
        contentEnrichmentTasks.values.forEach { $0.cancel() }
        for tab in NodeSeekNotificationTab.allCases {
            contentEnrichmentTokens[tab, default: 0] += 1
        }
        contentEnrichmentTasks.removeAll()
        contentEnrichmentRecordIDs.removeAll()
    }

    /// 两次刷新之间的最小间隔。
    ///
    /// `viewWillAppear` 与 `applicationDidBecomeActive` 在冷启动/前台恢复时会连着触发，
    /// 原来的 `guard refreshOperationTask == nil` 只挡得住真正并发的那一瞬间：任务一结束
    /// 守卫就放开，同一个 4 接口扫描会紧跟着再跑一轮。这里按时间窗口去重，
    /// 稍晚的补刷交给 90 秒循环。
    private static let minimumRefreshInterval: TimeInterval = 5
    private var lastRefreshStartedAt: Date?

    func refreshNow() {
        if let lastRefreshStartedAt,
           Date().timeIntervalSince(lastRefreshStartedAt) < Self.minimumRefreshInterval {
            return
        }
        guard refreshOperationTask == nil else { return }
        lastRefreshStartedAt = Date()
        refreshOperationToken &+= 1
        let token = refreshOperationToken

        refreshOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshCachedNotifications()
            guard self.refreshOperationToken == token else { return }
            self.refreshOperationTask = nil
        }
    }

    private func refreshCachedNotifications() async {
        guard let snapshot = await currentAccountStore.snapshot(),
              snapshot.account.isLoggedIn,
              let ownerID = snapshot.account.nodeSeekUID else {
            return
        }

        let atMeRecords: [NodeSeekNotificationRecord]
        do {
            atMeRecords = try await client.loadAtMe()
        } catch is CancellationError {
            return
        } catch {
            AppLog.debug(.service, "通知预加载 @我 失败: \(error.localizedDescription)")
            return
        }

        let cachedAtMeRecords = mergedNotificationRecords(
            atMeRecords,
            for: .atMe,
            ownerID: ownerID
        )
        NodeSeekNotificationMemoryCache.shared.store(
            records: cachedAtMeRecords,
            for: .atMe,
            ownerID: ownerID
        )
        NodeSeekNotificationCacheEvent.post(ownerID: ownerID)
        startContentEnrichment(for: cachedAtMeRecords, tab: .atMe, ownerID: ownerID)

        // @我成功返回后才开始后两个请求，避免首屏内容被并发网络请求拖慢。
        async let replyRecords = client.loadReplies()
        async let messageRecords = client.loadMessageConversations()
        async let unreadCount = client.loadUnreadCount()

        do {
            let records = try await replyRecords
            let cachedReplyRecords = mergedNotificationRecords(
                records,
                for: .reply,
                ownerID: ownerID
            )
            NodeSeekNotificationMemoryCache.shared.store(
                records: cachedReplyRecords,
                for: .reply,
                ownerID: ownerID
            )
            NodeSeekNotificationCacheEvent.post(ownerID: ownerID)
            startContentEnrichment(for: cachedReplyRecords, tab: .reply, ownerID: ownerID)
        } catch is CancellationError {
            return
        } catch {
            AppLog.debug(.service, "通知预加载 回复主题 失败: \(error.localizedDescription)")
        }

        do {
            let records = try await messageRecords
            NodeSeekNotificationMemoryCache.shared.store(
                messageRecords: NodeSeekMessageConversationRecord.latestConversations(
                    from: records,
                    currentUserID: ownerID
                ),
                ownerID: ownerID
            )
            NodeSeekNotificationCacheEvent.post(ownerID: ownerID)
        } catch is CancellationError {
            return
        } catch {
            AppLog.debug(.service, "通知预加载 私信 失败: \(error.localizedDescription)")
        }

        do {
            let count = try await unreadCount
            let reconciledCount = NodeSeekNotificationMemoryCache.shared.store(
                unreadCount: count,
                ownerID: ownerID
            ) ?? count
            // 消息列表可能尚未落地，reconcile 后再发布，避免陈旧 message 计数上角标。
            let badgeReadyCount = NodeSeekNotificationMemoryCache.shared.badgeReadyUnreadCount(
                reconciledCount,
                ownerID: ownerID
            )
            NodeSeekNotificationUnreadCountEvent.post(badgeReadyCount)
            NodeSeekNotificationCacheEvent.post(ownerID: ownerID)
        } catch is CancellationError {
            return
        } catch {
            AppLog.debug(.service, "通知预加载 未读数失败: \(error.localizedDescription)")
        }
    }

    private func mergedNotificationRecords(
        _ incomingRecords: [NodeSeekNotificationRecord],
        for tab: NodeSeekNotificationTab,
        ownerID: Int
    ) -> [NodeSeekNotificationRecord] {
        let cachedRecords: [NodeSeekNotificationRecord]
        switch tab {
        case .atMe:
            cachedRecords = NodeSeekNotificationMemoryCache.shared.snapshot(for: ownerID)?.atMeRecords ?? []
        case .reply:
            cachedRecords = NodeSeekNotificationMemoryCache.shared.snapshot(for: ownerID)?.replyRecords ?? []
        case .message:
            return incomingRecords
        }

        let cachedByID = Dictionary(uniqueKeysWithValues: cachedRecords.map { ($0.id, $0) })
        return incomingRecords.map { incomingRecord in
            guard let cachedRecord = cachedByID[incomingRecord.id] else { return incomingRecord }
            var mergedRecord = incomingRecord
            if mergedRecord.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                mergedRecord.content = cachedRecord.content
                mergedRecord.resolvedCommentPage = cachedRecord.resolvedCommentPage
            }
            if cachedRecord.isViewed {
                mergedRecord.viewed = 1
            }
            return mergedRecord
        }
    }

    private func startContentEnrichment(
        for records: [NodeSeekNotificationRecord],
        tab: NodeSeekNotificationTab,
        ownerID: Int
    ) {
        guard tab == .atMe || tab == .reply else { return }
        let allMissingContent = records.filter {
            $0.postID > 0 && ($0.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
        }
        let missingContent = Array(allMissingContent.prefix(Self.maximumContentEnrichmentRecords))
        guard missingContent.isEmpty == false else {
            cancelContentEnrichment(for: tab)
            return
        }

        if allMissingContent.count > missingContent.count {
            AppLog.info(
                .service,
                "通知正文补全已限量: tab=\(tab.title), queued=\(missingContent.count), deferred=\(allMissingContent.count - missingContent.count)"
            )
        }
        let recordIDs = Set(missingContent.map(\.id))
        if contentEnrichmentRecordIDs[tab] == recordIDs,
           contentEnrichmentTasks[tab] != nil {
            return
        }

        cancelContentEnrichment(for: tab)
        let token = contentEnrichmentTokens[tab, default: 0]
        contentEnrichmentRecordIDs[tab] = recordIDs
        let resolver = contentResolver
        let maximumConcurrentLoads = Self.maxConcurrentContentResolutions
        contentEnrichmentTasks[tab] = Task { [weak self, missingContent, resolver, maximumConcurrentLoads] in
            await withTaskGroup(of: (Int, NodeSeekNotificationContentResolver.ResolvedContent?).self) { group in
                var nextIndex = 0
                let initialTaskCount = min(maximumConcurrentLoads, missingContent.count)

                for _ in 0..<initialTaskCount {
                    let record = missingContent[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        (record.id, await resolver.resolveContent(for: record))
                    }
                }

                while let (recordID, resolvedContent) = await group.next() {
                    guard Task.isCancelled == false else {
                        group.cancelAll()
                        return
                    }
                    if let resolvedContent,
                       resolvedContent.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        await self?.storeResolvedContent(
                            resolvedContent,
                            forRecordID: recordID,
                            tab: tab,
                            ownerID: ownerID,
                            token: token
                        )
                    }

                    guard nextIndex < missingContent.count else { continue }
                    let record = missingContent[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        (record.id, await resolver.resolveContent(for: record))
                    }
                }
            }
            await self?.finishContentEnrichment(for: tab, token: token)
        }
    }

    private func storeResolvedContent(
        _ resolvedContent: NodeSeekNotificationContentResolver.ResolvedContent,
        forRecordID recordID: Int,
        tab: NodeSeekNotificationTab,
        ownerID: Int,
        token: Int
    ) {
        guard contentEnrichmentTokens[tab] == token,
              let snapshot = NodeSeekNotificationMemoryCache.shared.snapshot(for: ownerID) else {
            return
        }

        var records: [NodeSeekNotificationRecord]
        switch tab {
        case .atMe:
            records = snapshot.atMeRecords ?? []
        case .reply:
            records = snapshot.replyRecords ?? []
        case .message:
            return
        }
        guard let index = records.firstIndex(where: { $0.id == recordID }),
              records[index].content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return
        }

        records[index].content = resolvedContent.content
        records[index].resolvedCommentPage = resolvedContent.page
        NodeSeekNotificationMemoryCache.shared.store(records: records, for: tab, ownerID: ownerID)
        NodeSeekNotificationCacheEvent.post(ownerID: ownerID)
    }

    private func cancelContentEnrichment(for tab: NodeSeekNotificationTab) {
        contentEnrichmentTokens[tab, default: 0] += 1
        contentEnrichmentTasks[tab]?.cancel()
        contentEnrichmentTasks[tab] = nil
        contentEnrichmentRecordIDs[tab] = nil
    }

    private func finishContentEnrichment(for tab: NodeSeekNotificationTab, token: Int) {
        guard contentEnrichmentTokens[tab] == token else { return }
        contentEnrichmentTasks[tab] = nil
        contentEnrichmentRecordIDs[tab] = nil
    }
}
