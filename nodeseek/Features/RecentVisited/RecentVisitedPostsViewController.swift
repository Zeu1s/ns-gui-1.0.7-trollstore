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
        reloadRecords()
    }

    // 从底栏进入历史列表时刷新；详情页在导航栈顶时不会调用此方法。
    func refreshFromTabSelection() {
        reloadRecords()
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

    private func reloadRecords() {
        hasMoreRecords = true
        records.removeAll()
        listView.setItems([])
        loadNextPageIfNeeded()
        listView.hideRefreshing()
        updateEmptyState()
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
    }

    private func postItem(from record: VisitedPostRecord) -> PostListItem {
        let relativeDate = relativeDateFormatter.localizedString(for: record.visitedAt, relativeTo: Date())
        let post = PostSummary(
            id: record.postID,
            title: record.title,
            url: record.url,
            authorName: "最近浏览",
            nodeName: nil,
            replyCount: record.replyCount,
            viewCount: record.viewCount,
            lastActivityText: "浏览于 \(relativeDate)",
            avatarURL: record.avatarURL
        )
        // 历史记录使用首页同一张帖子卡片，但不额外将标题置灰。
        return PostListItem(post: post, isVisited: false)
    }

    private func updateEmptyState() {
        let isEmpty = records.isEmpty
        emptyLabel.isHidden = !isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = !isEmpty
    }

    private static let pageSize = 30
}

extension RecentVisitedPostsViewController: PostTextureListViewDelegate {
    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int) {
        guard records.indices.contains(index) else { return }
        onSelectRecord?(records[index])
    }

    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView) {
        reloadRecords()
    }

    func postTextureListViewDidRequestFirstPageRetry(_ textureListView: PostTextureListView) {
        reloadRecords()
    }

    func postTextureListView(
        _ textureListView: PostTextureListView,
        didApproachBottomAt index: Int,
        totalCount: Int
    ) {
        loadNextPageIfNeeded()
    }
}
