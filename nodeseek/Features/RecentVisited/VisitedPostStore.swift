//
//  VisitedPostStore.swift
//  nodeseek
//
//  Created by Codex on 2026/5/1.
//

import Foundation

nonisolated struct VisitedPostRecord: Equatable, Sendable {
    let postID: String
    let title: String
    let url: URL
    let visitedAt: Date
    let avatarURL: URL?
    let viewCount: Int
    let replyCount: Int

    init(
        postID: String,
        title: String,
        url: URL,
        visitedAt: Date,
        avatarURL: URL?,
        viewCount: Int = 0,
        replyCount: Int = 0
    ) {
        self.postID = postID
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
        self.avatarURL = avatarURL
        self.viewCount = viewCount
        self.replyCount = replyCount
    }
}

nonisolated struct PostListItem: Equatable, Sendable {
    let post: PostSummary
    let isVisited: Bool
}

@MainActor
protocol VisitedPostStoreProtocol: AnyObject {
    func isVisited(postID: String) -> Bool
    func markVisited(post: PostSummary, visitedAt: Date)
    func recentRecords(limit: Int) -> [VisitedPostRecord]
    func recentRecords(offset: Int, limit: Int) -> [VisitedPostRecord]
    /// 按帖子 ID 取一条历史记录。列表页每行都要查统计数，必须是 O(1)。
    func record(forPostID postID: String) -> VisitedPostRecord?
    func updateMetadata(_ records: [VisitedPostRecord])
    func clearAll()
}

extension VisitedPostStoreProtocol {
    /// 兼容旧测试桩；真实存储会覆写并持久化刷新后的头像与统计。
    func updateMetadata(_ records: [VisitedPostRecord]) {}

    /// 测试桩与空实现的兜底：没有索引时退回线性查找，行为与原来一致。
    func record(forPostID postID: String) -> VisitedPostRecord? {
        recentRecords(limit: Int.max).first { $0.postID == postID }
    }
}

protocol VisitedPostPersistence: AnyObject, Sendable {
    func loadRecent(limit: Int) throws -> [VisitedPostRecord]
    func upsert(_ record: VisitedPostRecord) throws
    func upsert(_ records: [VisitedPostRecord], keepingLatest limit: Int) throws
    func trim(keepingLatest limit: Int) throws
    func deleteAll() throws
}

@MainActor
final class VisitedPostStore: VisitedPostStoreProtocol {
    nonisolated static let defaultLimit = 1500

    private let persistence: VisitedPostPersistence
    private let limit: Int
    private let writeQueue: DispatchQueue
    private var records: [VisitedPostRecord]
    private var visitedIDs: Set<String>
    /// postID -> 记录下标。列表页每行都要按 postID 查统计数，
    /// 原来每行都 `recentRecords(limit: Int.max)`（整份拷贝最多 1500 条）再线性查找。
    private var recordIndexByPostID: [String: Int] = [:]
    private var pendingRecords: [VisitedPostRecord] = []
    private var scheduledFlushWorkItem: DispatchWorkItem?

    init(
        persistence: VisitedPostPersistence,
        limit: Int = VisitedPostStore.defaultLimit,
        writeQueue: DispatchQueue = DispatchQueue(label: "com.nodeseek.app.visited-post-store")
    ) {
        self.persistence = persistence
        self.limit = limit
        self.writeQueue = writeQueue

        let loadedRecords = (try? persistence.loadRecent(limit: limit)) ?? []
        let trimmedRecords = Array(loadedRecords.prefix(limit))
        self.records = trimmedRecords
        self.visitedIDs = Set(trimmedRecords.map(\.postID))
        rebuildRecordIndex()
    }

    private func rebuildRecordIndex() {
        // 用循环而不是 Dictionary(uniqueKeysWithValues:)：磁盘数据理论上可能含重复
        // postID（旧版本写入或异常中断），那种输入会让 uniqueKeysWithValues 直接崩。
        // 重复时保留最靠前（最新）的那条。
        var index: [String: Int] = [:]
        index.reserveCapacity(records.count)
        for (offset, record) in records.enumerated() where index[record.postID] == nil {
            index[record.postID] = offset
        }
        recordIndexByPostID = index
    }

    func isVisited(postID: String) -> Bool {
        visitedIDs.contains(postID)
    }

    func record(forPostID postID: String) -> VisitedPostRecord? {
        guard let index = recordIndexByPostID[postID], records.indices.contains(index) else { return nil }
        return records[index]
    }

    func markVisited(post: PostSummary, visitedAt: Date) {
        let record = VisitedPostRecord(
            postID: post.id,
            title: post.title,
            url: post.url,
            visitedAt: visitedAt,
            avatarURL: post.avatarURL,
            viewCount: post.viewCount,
            replyCount: post.replyCount
        )

        records.removeAll { $0.postID == record.postID }
        records.insert(record, at: 0)
        if records.count > limit {
            records = Array(records.prefix(limit))
        }
        visitedIDs = Set(records.map(\.postID))
        rebuildRecordIndex()

        pendingRecords.append(record)
        scheduleFlush()
    }

    func recentRecords(limit: Int) -> [VisitedPostRecord] {
        recentRecords(offset: 0, limit: limit)
    }

    func recentRecords(offset: Int, limit: Int) -> [VisitedPostRecord] {
        let safeOffset = max(0, offset)
        let safeLimit = max(0, limit)
        guard safeLimit > 0, safeOffset < records.count else { return [] }
        return Array(records.dropFirst(safeOffset).prefix(safeLimit))
    }

    func updateMetadata(_ updatedRecords: [VisitedPostRecord]) {
        guard updatedRecords.isEmpty == false else { return }
        let recordsByID = Dictionary(uniqueKeysWithValues: updatedRecords.map { ($0.postID, $0) })
        var changed: [VisitedPostRecord] = []
        records = records.map { existing in
            guard let updated = recordsByID[existing.postID], updated != existing else { return existing }
            changed.append(updated)
            return updated
        }
        guard changed.isEmpty == false else { return }
        // 只替换了同位置元素，但保持索引与数组一致仍是最省心的做法。
        rebuildRecordIndex()
        pendingRecords.append(contentsOf: changed)
        scheduleFlush()
    }

    func clearAll() {
        scheduledFlushWorkItem?.cancel()
        scheduledFlushWorkItem = nil
        pendingRecords.removeAll()
        records.removeAll()
        visitedIDs.removeAll()
        recordIndexByPostID.removeAll()

        let persistence = persistence
        writeQueue.async {
            try? persistence.deleteAll()
        }
    }

    func flush() {
        scheduledFlushWorkItem?.cancel()
        scheduledFlushWorkItem = nil
        flushPendingRecords()
    }

    private func scheduleFlush() {
        scheduledFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingRecords()
            }
        }
        scheduledFlushWorkItem = workItem
        writeQueue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func flushPendingRecords() {
        guard !pendingRecords.isEmpty else { return }
        let recordsToPersist = coalescedPendingRecords(pendingRecords)
        pendingRecords.removeAll()
        let persistence = persistence
        let limit = limit

        writeQueue.async {
            do {
                try persistence.upsert(recordsToPersist, keepingLatest: limit)
            } catch {
                // UI 已经按内存状态更新，持久化失败不回滚用户可见状态。
            }
        }
    }

    private func coalescedPendingRecords(_ records: [VisitedPostRecord]) -> [VisitedPostRecord] {
        var orderedIDs: [String] = []
        var latestRecordByID: [String: VisitedPostRecord] = [:]

        for record in records {
            if latestRecordByID[record.postID] == nil {
                orderedIDs.append(record.postID)
            }
            if let existing = latestRecordByID[record.postID],
               existing.visitedAt > record.visitedAt {
                continue
            }
            latestRecordByID[record.postID] = record
        }

        return orderedIDs.compactMap { latestRecordByID[$0] }
    }
}

@MainActor
final class EmptyVisitedPostStore: VisitedPostStoreProtocol {
    nonisolated init() {}

    func isVisited(postID: String) -> Bool {
        false
    }

    func markVisited(post: PostSummary, visitedAt: Date) {
    }

    func recentRecords(limit: Int) -> [VisitedPostRecord] {
        []
    }

    func recentRecords(offset: Int, limit: Int) -> [VisitedPostRecord] {
        []
    }

    func record(forPostID postID: String) -> VisitedPostRecord? {
        nil
    }

    func clearAll() {
    }
}
