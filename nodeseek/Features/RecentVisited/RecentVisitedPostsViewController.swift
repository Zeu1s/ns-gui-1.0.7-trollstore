//
//  RecentVisitedPostsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import UIKit

@MainActor
final class RecentVisitedPostsViewController: UIViewController {
    var onSelectRecord: ((VisitedPostRecord) -> Void)?

    private let visitedStore: VisitedPostStoreProtocol
    private let listView = PostTextureListView()
    private let emptyLabel = UILabel()
    private var records: [VisitedPostRecord] = []
    private var resolvedPostSummaries: [String: PostSummary] = [:]
    private var metadataRefreshGeneration = 0
    private var hasMoreRecords = true
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    init(visitedStore: VisitedPostStoreProtocol) {
        self.visitedStore = visitedStore
        super.init(nibName: nil, bundle: nil)
        title = "最近浏览"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.hidesBackButton = true
        configureList()
        configureEmptyState()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearButtonTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "清除浏览记录"
        reloadRecords(refreshMetadata: true)
    }

    // 从底栏进入历史列表时刷新；详情页在导航栈顶时不会调用此方法。
    func refreshFromTabSelection() {
        reloadRecords(refreshMetadata: true)
    }

    /// 切回历史 tab 时重播流式呈现。
    func replayStreamAppearance() {
        listView.replayStreamAppearance()
    }

    private func configureList() {
        listView.delegate = self
        listView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(listView)
        NSLayoutConstraint.activate([
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.topAnchor.constraint(equalTo: view.topAnchor),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureEmptyState() {
        emptyLabel.text = "暂无最近浏览"
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.accessibilityIdentifier = "recent-visited-posts-empty-label"
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func clearButtonTapped() {
        let alert = UIAlertController(
            title: "清除浏览记录？",
            message: "这会删除所有最近浏览记录，此操作无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.clearAllRecords()
        })
        present(alert, animated: true)
    }

    private func clearAllRecords() {
        visitedStore.clearAll()
        records.removeAll()
        hasMoreRecords = false
        listView.setItems([])
        updateEmptyState()
    }

    private func reloadRecords(refreshMetadata: Bool = false) {
        let firstPage = visitedStore.recentRecords(offset: 0, limit: Self.pageSize)
        records = firstPage
        hasMoreRecords = firstPage.count == Self.pageSize
        renderRecordsPreservingViewport()
        listView.hideRefreshing()
        updateEmptyState()
        if refreshMetadata {
            refreshPostMetadata(for: firstPage)
        }
    }

    private func loadNextPageIfNeeded() {
        guard hasMoreRecords else { return }
        let nextRecords = visitedStore.recentRecords(offset: records.count, limit: Self.pageSize)
        guard !nextRecords.isEmpty else {
            hasMoreRecords = false
            updateEmptyState()
            return
        }

        records.append(contentsOf: nextRecords)
        hasMoreRecords = nextRecords.count == Self.pageSize
        listView.setItems(records.map(postItem(from:)))
        updateEmptyState()
        refreshPostMetadata(for: nextRecords)
    }

    private func postItem(from record: VisitedPostRecord) -> PostListItem {
        let relativeDate = relativeDateFormatter.localizedString(for: record.visitedAt, relativeTo: Date())
        let resolvedSummary = resolvedPostSummaries[record.postID]
        let resolvedAuthorName = (resolvedSummary?.authorName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let post = PostSummary(
            id: record.postID,
            title: record.title,
            url: record.url,
            authorName: resolvedAuthorName.isEmpty ? "最近浏览" : resolvedAuthorName,
            nodeName: resolvedSummary?.nodeName,
            replyCount: max(resolvedSummary?.replyCount ?? 0, record.replyCount),
            viewCount: max(resolvedSummary?.viewCount ?? 0, record.viewCount),
            lastActivityText: "浏览于 \(relativeDate)",
            avatarURL: resolvedSummary?.avatarURL ?? record.avatarURL,
            authorProfileURL: resolvedSummary?.authorProfileURL,
            authorBadgeTexts: resolvedSummary?.authorBadgeTexts ?? []
        )
        // 历史记录使用首页同一张帖子卡片，但不额外将标题置灰。
        return PostListItem(post: post, isVisited: false)
    }

    private func updateEmptyState() {
        let isEmpty = records.isEmpty
        emptyLabel.isHidden = !isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = !isEmpty
    }

    private func refreshPostMetadata(for candidates: [VisitedPostRecord]) {
        // 板块名和头像一样要逐帖抓详情才有，但首页/分类列表早就把 nodeName
        // 解析进 PostSummaryResolver 的缓存了。先白拿一遍缓存：不花任何请求，
        // 从列表点进过的帖子立刻就能显示板块。
        applyCachedSummaries(for: candidates)

        // 只补真正缺头像的记录。此前整页 30 条无条件重打，而元数据早就写回了
        // visitedStore，等于每次进历史页都把同一批帖子再轰一遍。
        let pending = candidates.filter { $0.avatarURL == nil }
        guard pending.isEmpty == false else { return }
        metadataRefreshGeneration += 1
        let generation = metadataRefreshGeneration
        Task { [weak self] in
            var summaries: [String: PostSummary] = [:]
            var start = 0
            while start < pending.count {
                // 站点实测限制是"每过 2 秒才能试一次"。此前一批并发 4、批间只隔
                // 1.2 秒，等于约 3.3 请求/秒 —— 超出限制 6 倍多，一次会话打出
                // 141 次详情请求、130 次 429，并把后面所有 WebView 操作一起拖死。
                // 元数据只是头像和板块名，改成逐条 + 2.2 秒。
                let end = min(start + 1, pending.count)
                let batch = Array(pending[start..<end])
                await withTaskGroup(of: (String, PostSummary?).self) { group in
                    for record in batch {
                        group.addTask {
                            let summary = await PostSummaryResolver.shared.resolveHistoryMetadata(
                                postID: record.postID,
                                title: record.title,
                                fallbackViewCount: record.viewCount,
                                fallbackReplyCount: record.replyCount
                            )
                            return (record.postID, summary)
                        }
                    }
                    for await (postID, summary) in group {
                        if let summary {
                            summaries[postID] = summary
                        }
                    }
                }
                start = end
                if start < pending.count {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                }
            }
            guard let self, self.metadataRefreshGeneration == generation else { return }
            let refreshedRecords = self.records.map { record in
                guard let summary = summaries[record.postID] else { return record }
                return VisitedPostRecord(
                    postID: record.postID,
                    title: record.title,
                    url: record.url,
                    visitedAt: record.visitedAt,
                    avatarURL: summary.avatarURL ?? record.avatarURL,
                    viewCount: summary.viewCount,
                    replyCount: summary.replyCount
                )
            }
            guard refreshedRecords != self.records else { return }
            self.resolvedPostSummaries.merge(summaries) { _, new in new }
            self.visitedStore.updateMetadata(refreshedRecords)
            self.records = refreshedRecords
            self.renderRecordsPreservingViewport()
        }
    }

    /// 只读 PostSummaryResolver 已有缓存，不发任何请求。
    private func applyCachedSummaries(for candidates: [VisitedPostRecord]) {
        let generation = metadataRefreshGeneration
        Task { [weak self] in
            guard let self else { return }
            var filled: [String: PostSummary] = [:]
            for record in candidates {
                guard let summary = await PostSummaryResolver.shared.summary(for: record.postID) else {
                    continue
                }
                if summary.nodeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    filled[record.postID] = summary
                }
            }
            guard filled.isEmpty == false,
                  self.metadataRefreshGeneration == generation else { return }
            self.resolvedPostSummaries.merge(filled) { existing, new in
                existing.nodeName?.isEmpty == false ? existing : new
            }
            self.renderRecordsPreservingViewport()
        }
    }

    private func renderRecordsPreservingViewport() {
        listView.replaceItemsPreservingViewport(records.map(postItem(from:)))
    }

    private static let pageSize = 30
}

extension RecentVisitedPostsViewController: PostTextureListViewDelegate {
    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int) {
        guard records.indices.contains(index) else { return }
        onSelectRecord?(records[index])
    }

    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView) {
        reloadRecords(refreshMetadata: true)
    }

    func postTextureListViewDidRequestFirstPageRetry(_ textureListView: PostTextureListView) {
        reloadRecords(refreshMetadata: true)
    }

    func postTextureListView(
        _ textureListView: PostTextureListView,
        didApproachBottomAt index: Int,
        totalCount: Int
    ) {
        loadNextPageIfNeeded()
    }
}
