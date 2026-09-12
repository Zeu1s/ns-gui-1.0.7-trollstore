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

    private func reconciledUnreadCount(
        _ remoteCount: NodeSeekNotificationUnreadCount
    ) -> NodeSeekNotificationUnreadCount {
        var reconciled = remoteCount
        if let atMeRecords {
            reconciled.setCount(
                atMeRecords.reduce(0) { $0 + ($1.isViewed ? 0 : $1.displayUnreadCount) },
                for: .atMe
            )
        }
        if let replyRecords {
            reconciled.setCount(
                replyRecords.reduce(0) { $0 + ($1.isViewed ? 0 : $1.displayUnreadCount) },
                for: .reply
            )
        }
        if let messageRecords {
            reconciled.setCount(
                messageRecords.reduce(0) { $0 + ($1.isViewed ? 0 : $1.displayUnreadCount) },
                for: .message
            )
        }
        return reconciled
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

    func isViewed(id: Int, tab: NodeSeekNotificationTab, ownerID: Int?) -> Bool {
        guard let ownerID, id > 0 else { return false }
        return identifiers(for: tab, ownerID: ownerID).contains(id)
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

    private static let refreshInterval: UInt64 = 45_000_000_000

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
    private static let maxConcurrentContentResolutions = 1
    private static let maximumContentEnrichmentRecords = 30

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

    func refreshNow() {
        guard refreshOperationTask == nil else { return }
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
            NodeSeekNotificationUnreadCountEvent.post(reconciledCount)
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
