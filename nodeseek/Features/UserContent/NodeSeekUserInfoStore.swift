//
//  NodeSeekUserInfoStore.swift
//  nodeseek
//

import Foundation

final class NodeSeekUserInfoStore {
    static let shared = NodeSeekUserInfoStore()
    static let didUpdateNotification = Notification.Name("NodeSeekUserInfoStore.didUpdate")

    private let client: NodeSeekUserInfoLoading
    private let defaults: UserDefaults
    /// 下面这几个集合会被**多个线程同时碰**：`badgeText(for:)` / `requestBadge(for:)`
    /// 是在 CommentCellNode 的构造和排版里调用的，而 Texture 会在自己的后台分配线程上
    /// 并发创建这些节点（真机崩溃报告里 Thread 5/6/7 三条栈同时停在
    /// `-[ASDataController _allocateNodesFromElements:strictlyOnCurrentThread:]`）；
    /// 写入侧又在 `MainActor.run` 里改同一批字典。Swift 的 Dictionary/Array 不是线程安全的，
    /// 并发读写就是这种 `SEGV_ACCERR at 0x8000000000000010`（垃圾指针）。
    /// 所有读写都必须过这把锁；持锁期间不得 await，所以不会和 MainActor 互相等。
    private let stateLock = NSLock()
    /// 别人的资料可以缓存，但不该缓存到永远：等级、徽章这类是会变的，
    /// 原实现内存里从不过期，于是一个会话里第一次看到的徽章会一直挂着。
    private var cache: [Int: (info: NodeSeekUserInfo, fetchedAt: Date)] = [:]
    private var inflight: [Int: Task<Void, Never>] = [:]
    private var pendingIDs: [Int] = []
    private var activeCount = 0
    private let maxConcurrent = 6
    private static let memoryCacheTTL: TimeInterval = 600

    init(client: NodeSeekUserInfoLoading = NodeSeekUserInfoClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    func badgeText(for profileURL: URL?) -> String? {
        guard let userID = Self.userID(from: profileURL) else { return nil }
        stateLock.lock()
        defer { stateLock.unlock() }
        if let entry = cache[userID], Self.isFresh(entry) {
            return entry.info.badgeText
        }
        return cachedDefaultsBadgeText(for: userID)
    }

    func requestBadge(for profileURL: URL?) {
        guard let userID = Self.userID(from: profileURL) else { return }
        stateLock.lock()
        guard cache[userID].map(Self.isFresh) != true,
              inflight[userID] == nil,
              pendingIDs.contains(userID) == false else {
            stateLock.unlock()
            return
        }
        pendingIDs.append(userID)
        stateLock.unlock()
        startPendingRequests()
    }

    private static func isFresh(_ entry: (info: NodeSeekUserInfo, fetchedAt: Date)) -> Bool {
        Date().timeIntervalSince(entry.fetchedAt) < memoryCacheTTL
    }

    /// 内存缓存上限：原来只按 TTL 判断新旧，过期条目永远留在字典里，
    /// 一个会话里看过的所有人都常驻内存。这里按写入顺序淘汰最旧的。
    private static let maximumCacheCount = 400
    private var cacheInsertionOrder: [Int] = []

    /// 调用方必须已持有 `stateLock`。
    private func evictCacheIfNeeded() {
        while cacheInsertionOrder.count > Self.maximumCacheCount {
            let oldest = cacheInsertionOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    /// UserDefaults 读一次就够：cell 复用时会按行反复取徽章文本，
    /// 每次未命中都打一遍磁盘不值得。
    private var defaultsBadgeCache: [Int: String] = [:]
    private var defaultsBadgeInsertionOrder: [Int] = []

    /// 调用方必须已持有 `stateLock` —— 它会写 `defaultsBadgeCache`。
    private func cachedDefaultsBadgeText(for userID: Int) -> String? {
        if let cached = defaultsBadgeCache[userID] {
            return cached.isEmpty ? nil : cached
        }
        let value = defaults.string(forKey: Self.cacheKey(userID))
        if defaultsBadgeCache.count >= Self.maximumCacheCount,
           defaultsBadgeInsertionOrder.isEmpty == false {
            let oldest = defaultsBadgeInsertionOrder.removeFirst()
            defaultsBadgeCache.removeValue(forKey: oldest)
        }
        defaultsBadgeCache[userID] = value ?? ""
        defaultsBadgeInsertionOrder.append(userID)
        return value
    }

    /// 在锁内把待办取出来发起，Task 的回调再单独进锁写状态。
    /// 绝不在持锁时 await，也绝不在锁外改这几个集合。
    private func startPendingRequests() {
        stateLock.lock()
        var started: [Int] = []
        while activeCount < maxConcurrent, let userID = pendingIDs.first {
            pendingIDs.removeFirst()
            activeCount += 1
            started.append(userID)
        }
        for userID in started {
            inflight[userID] = makeRequestTask(for: userID)
        }
        stateLock.unlock()
    }

    private func makeRequestTask(for userID: Int) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                if let info = try await self?.client.loadUserInfo(userID: userID) {
                    await self?.applyLoadedUserInfo(info, for: userID)
                }
            } catch {
                // 单次失败不重试，避免在弱网下打满接口。
            }
            await self?.finishRequest(for: userID)
        }
    }

    private func applyLoadedUserInfo(_ info: NodeSeekUserInfo, for userID: Int) async {
        stateLock.lock()
        if cache[userID] == nil {
            cacheInsertionOrder.append(userID)
        }
        cache[userID] = (info, Date())
        evictCacheIfNeeded()
        defaultsBadgeCache[userID] = info.badgeText
        defaults.set(info.badgeText, forKey: Self.cacheKey(userID))
        stateLock.unlock()
        // 通知留在锁外，且回主线程发：观察者会在回调里重排 UI。
        await MainActor.run {
            NotificationCenter.default.post(
                name: Self.didUpdateNotification,
                object: nil,
                userInfo: ["userID": userID]
            )
        }
    }

    private func finishRequest(for userID: Int) async {
        stateLock.lock()
        inflight[userID] = nil
        activeCount -= 1
        stateLock.unlock()
        startPendingRequests()
    }

    private static func cacheKey(_ userID: Int) -> String {
        "nodeseek.userInfo.\(userID)"
    }

    static func userID(from profileURL: URL?) -> Int? {
        profileURL.flatMap(NodeSeekUserIDResolver.uid(from:))
    }
}
