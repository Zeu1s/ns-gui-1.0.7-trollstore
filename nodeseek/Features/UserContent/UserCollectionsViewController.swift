//
//  UserCollectionsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import AsyncDisplayKit
import UIKit

@MainActor
final class UserCollectionsViewController: UIViewController {
    private let tableNode = ASTableNode(style: .plain)
    private let refreshControl = UIRefreshControl()
    private let footerView = UserContentFooterView()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "user-collections-error-view")
    private let client: NodeSeekUserContentClient
    private let collectionSubmitter: PostCollectionSubmitting
    private let currentAccountStore: CurrentAccountStore
    private let visitedStore: VisitedPostStoreProtocol
    private let requestedUserID: Int?
    private var records: [UserCollectionRecord] = []
    private var resolvedPostSummaries: [Int: PostSummary] = [:]
    private var summaryRefreshGeneration = 0
    private var displayMode: UserContentDisplayMode = .content
    private var uid: Int?
    private var nextPage = 2
    private var hasMorePages = true
    private var isLoadingFirstPage = false
    private var isLoadingMore = false
    private var isCurrentUsersCollection = false
    private var removalInProgressPostID: Int?
    private var lastBatchFetchRequestedCount: Int?
    private var shouldStreamContentAppearance = false
    private let skeletonRowCount = 9
    var onSelectPost: ((PostSummary, Int, String?) -> Void)?

    init(
        userID: Int? = nil,
        authorName _: String? = nil,
        avatarURL _: URL? = nil,
        client: NodeSeekUserContentClient? = nil,
        collectionSubmitter: PostCollectionSubmitting? = nil,
        currentAccountStore: CurrentAccountStore = .shared,
        visitedStore: VisitedPostStoreProtocol = VisitedPostStore.shared
    ) {
        requestedUserID = userID
        self.client = client ?? NodeSeekUserContentClient()
        self.collectionSubmitter = collectionSubmitter ?? NodeSeekPostCollectionSubmitter()
        self.currentAccountStore = currentAccountStore
        self.visitedStore = visitedStore
        super.init(nibName: nil, bundle: nil)
        title = "收藏"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        observeTextSizeChanges()
        loadFirstPage()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.leadingScreensForBatching = 2
        tableNode.view.separatorStyle = .singleLine
        tableNode.view.tableFooterView = footerView
        tableNode.view.backgroundColor = .systemBackground
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableNode.view.refreshControl = refreshControl
        let removeSwipe = UISwipeGestureRecognizer(target: self, action: #selector(removeSwipeRecognized(_:)))
        removeSwipe.direction = .left
        removeSwipe.cancelsTouchesInView = false
        tableNode.view.addGestureRecognizer(removeSwipe)
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false
        errorView.onRetry = { [weak self] in
            self?.loadFirstPage()
        }

        view.addSubview(tableNode.view)
        view.addSubview(errorView)
        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: view.topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func loadFirstPage() {
        guard !isLoadingFirstPage else { return }
        isLoadingFirstPage = true
        hasMorePages = true
        nextPage = 2
        lastBatchFetchRequestedCount = nil
        showSkeleton()

        Task { [weak self] in
            guard let self else { return }
            do {
                let uid = try await resolveUID()
                let loaded = try await client.loadCollections(page: 1, uid: uid)
                self.uid = uid
                let currentUserID = await currentAccountStore.snapshot()?.account.nodeSeekUID
                isCurrentUsersCollection = currentUserID == uid
                finishFirstPage(records: loaded)
            } catch {
                showFirstPageError(error.localizedDescription)
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard let uid else { return }
        guard !records.isEmpty, hasMorePages, !isLoadingMore, !isLoadingFirstPage else { return }
        isLoadingMore = true
        footerView.startAnimating()
        let page = nextPage
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await client.loadCollections(page: page, uid: uid)
                finishLoadMore(records: loaded, page: page)
            } catch {
                isLoadingMore = false
                footerView.stopAnimating()
            }
        }
    }

    private func resolveUID() async throws -> Int {
        if let requestedUserID {
            return requestedUserID
        }
        guard let snapshot = await currentAccountStore.snapshot(),
              let uid = snapshot.account.nodeSeekUID else {
            throw UserContentViewError.missingUID
        }
        return uid
    }

    private func finishFirstPage(records: [UserCollectionRecord]) {
        self.records = records
        resolvedPostSummaries.removeAll()
        displayMode = .content
        isLoadingFirstPage = false
        isLoadingMore = false
        hasMorePages = !records.isEmpty
        errorView.isHidden = true
        refreshControl.endRefreshing()
        footerView.stopAnimating()
        shouldStreamContentAppearance = true
        tableNode.reloadData()
        streamVisibleRowsIfNeeded()
        refreshPostSummaries(for: records)
    }

    private func finishLoadMore(records loaded: [UserCollectionRecord], page: Int) {
        isLoadingMore = false
        footerView.stopAnimating()
        guard !loaded.isEmpty else {
            hasMorePages = false
            return
        }
        nextPage = page + 1
        let oldCount = records.count
        records.append(contentsOf: loaded.filter { item in
            records.contains { $0.postID == item.postID } == false
        })
        let newCount = records.count
        guard newCount > oldCount else { return }
        let indexPaths = (oldCount..<newCount).map { IndexPath(row: $0, section: 0) }
        tableNode.performBatch(animated: false) { [weak self] in
            self?.tableNode.insertRows(at: indexPaths, with: .none)
        }
        refreshPostSummaries(for: Array(records[oldCount..<newCount]))
    }

    private func showSkeleton() {
        displayMode = .skeleton
        records = []
        resolvedPostSummaries.removeAll()
        summaryRefreshGeneration += 1
        errorView.isHidden = true
        footerView.stopAnimating()
        tableNode.reloadData()
    }

    private func showFirstPageError(_ message: String) {
        displayMode = .firstPageError
        records = []
        isLoadingFirstPage = false
        isLoadingMore = false
        refreshControl.endRefreshing()
        footerView.stopAnimating()
        errorView.messageLabel.text = message
        errorView.isHidden = false
        tableNode.reloadData()
    }

    @objc private func refreshTriggered() {
        guard !isLoadingFirstPage else { return }
        loadFirstPage()
    }

    private func observeTextSizeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appTextSizeDidChange(_:)),
            name: AppTextSizeSettings.didChangeNotification,
            object: nil
        )
    }

    @objc private func appTextSizeDidChange(_ notification: Notification) {
        guard displayMode == .content else { return }
        tableNode.reloadData()
    }

    private func openRecord(_ record: UserCollectionRecord) {
        onSelectPost?(postSummary(for: record), 1, nil)
    }

    @objc private func removeSwipeRecognized(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.state == .ended,
              isCurrentUsersCollection,
              displayMode == .content,
              removalInProgressPostID == nil else {
            return
        }
        let location = recognizer.location(in: tableNode.view)
        guard let indexPath = tableNode.view.indexPathForRow(at: location),
              records.indices.contains(indexPath.row) else {
            return
        }
        confirmRemove(records[indexPath.row])
    }

    private func confirmRemove(_ record: UserCollectionRecord) {
        let alert = UIAlertController(
            title: "取消收藏",
            message: "将从收藏中移除“\(record.title)”。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "取消收藏", style: .destructive) { [weak self] _ in
            self?.remove(record)
        })
        present(alert, animated: true)
    }

    private func remove(_ record: UserCollectionRecord) {
        guard removalInProgressPostID == nil else { return }
        removalInProgressPostID = record.postID
        let referer = NodeSeekSite.postURL(id: "\(record.postID)", page: 1)
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await collectionSubmitter.removeFavorite(
                    postID: "\(record.postID)",
                    referer: referer
                )
                guard Task.isCancelled == false else { return }
                finishRemoving(record)
            } catch {
                guard Task.isCancelled == false else { return }
                removalInProgressPostID = nil
                presentRemovalError(error.localizedDescription)
            }
        }
    }

    private func finishRemoving(_ record: UserCollectionRecord) {
        removalInProgressPostID = nil
        guard let index = records.firstIndex(where: { $0.postID == record.postID }) else { return }
        let indexPath = IndexPath(row: index, section: 0)
        tableNode.performBatch(animated: true) { [weak self] in
            guard let self else { return }
            self.records.remove(at: index)
            self.tableNode.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    private func presentRemovalError(_ message: String) {
        let alert = UIAlertController(title: "取消收藏失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    private func postSummary(for record: UserCollectionRecord) -> PostSummary {
        let resolvedSummary = resolvedPostSummaries[record.postID]
        let resolvedAuthorName = (resolvedSummary?.authorName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cachedStatistics = visitedStore
            .recentRecords(limit: Int.max)
            .first { $0.postID == "\(record.postID)" }
        return PostSummary(
            id: "\(record.postID)",
            title: record.title,
            url: NodeSeekSite.postURL(id: "\(record.postID)", page: 1),
            authorName: resolvedAuthorName.isEmpty ? record.authorName ?? "" : resolvedAuthorName,
            nodeName: resolvedSummary?.nodeName,
            replyCount: max(max(resolvedSummary?.replyCount ?? 0, record.replyCount ?? 0), cachedStatistics?.replyCount ?? 0),
            viewCount: max(max(resolvedSummary?.viewCount ?? 0, record.viewCount ?? 0), cachedStatistics?.viewCount ?? 0),
            lastActivityText: record.lastActivityText,
            avatarURL: resolvedSummary?.avatarURL ?? record.avatarURL,
            authorProfileURL: resolvedSummary?.authorProfileURL,
            authorBadgeTexts: resolvedSummary?.authorBadgeTexts ?? []
        )
    }

    private func refreshPostSummaries(for candidates: [UserCollectionRecord]) {
        guard candidates.isEmpty == false else { return }
        summaryRefreshGeneration += 1
        let generation = summaryRefreshGeneration
        var cachedViewCounts: [Int: Int] = [:]
        var cachedReplyCounts: [Int: Int] = [:]
        for record in candidates {
            let cached = visitedStore
                .recentRecords(limit: Int.max)
                .first { $0.postID == "\(record.postID)" }
            cachedViewCounts[record.postID] = max(cachedViewCounts[record.postID] ?? 0, cached?.viewCount ?? 0)
            cachedReplyCounts[record.postID] = max(cachedReplyCounts[record.postID] ?? 0, cached?.replyCount ?? 0)
        }
        Task { [weak self] in
            var refreshed: [Int: PostSummary] = [:]
            var start = 0
            while start < candidates.count {
                let end = min(start + 4, candidates.count)
                let batch = Array(candidates[start..<end])
                await withTaskGroup(of: (Int, PostSummary?).self) { group in
                    for record in batch {
                        group.addTask {
                            let summary = await PostSummaryResolver.shared.resolveHistoryMetadata(
                                postID: "\(record.postID)",
                                title: record.title,
                                fallbackViewCount: max(record.viewCount ?? 0, cachedViewCounts[record.postID] ?? 0),
                                fallbackReplyCount: max(record.replyCount ?? 0, cachedReplyCounts[record.postID] ?? 0)
                            )
                            return (record.postID, summary)
                        }
                    }
                    for await (postID, summary) in group {
                        if let summary {
                            refreshed[postID] = summary
                        }
                    }
                }
                start = end
            }
            await MainActor.run { [weak self] in
                guard let self,
                      self.summaryRefreshGeneration == generation,
                      self.displayMode == .content else { return }
                let relevantIDs = Set(self.records.map(\.postID))
                let applicable = refreshed.filter { relevantIDs.contains($0.key) }
                guard applicable.isEmpty == false else { return }
                self.resolvedPostSummaries.merge(applicable) { _, new in new }
                self.tableNode.reloadData()
            }
        }
    }

    private func streamVisibleRowsIfNeeded() {
        guard shouldStreamContentAppearance else { return }
        shouldStreamContentAppearance = false
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tableNode.view.window != nil else { return }
            self.tableNode.view.layoutIfNeeded()
            let cells = self.tableNode.view.visibleCells
                .sorted { $0.frame.minY < $1.frame.minY }
            for (index, cell) in cells.enumerated() {
                cell.alpha = 0
                cell.transform = CGAffineTransform(translationX: 0, y: 16).scaledBy(x: 0.98, y: 0.98)
                UIView.animate(
                    withDuration: 0.42,
                    delay: Double(index) * 0.03,
                    usingSpringWithDamping: 0.86,
                    initialSpringVelocity: 0.4,
                    options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
                ) {
                    cell.alpha = 1
                    cell.transform = .identity
                }
            }
        }
    }
}

extension UserCollectionsViewController: ASTableDataSource {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        switch displayMode {
        case .content:
            return records.count
        case .skeleton:
            return skeletonRowCount
        case .firstPageError:
            return 0
        }
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        switch displayMode {
        case .content:
            let record = records[indexPath.row]
            let post = postSummary(for: record)
            return {
                PostSummaryCellNode(post: post)
            }
        case .skeleton:
            return {
                UserContentSkeletonCellNode()
            }
        case .firstPageError:
            return {
                ASCellNode()
            }
        }
    }
}

extension UserCollectionsViewController: ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content, records.indices.contains(indexPath.row) else { return }
        tableNode.deselectRow(at: indexPath, animated: true)
        openRecord(records[indexPath.row])
    }

    func shouldBatchFetch(for tableNode: ASTableNode) -> Bool {
        displayMode == .content
            && !records.isEmpty
            && lastBatchFetchRequestedCount != records.count
    }

    func tableNode(_ tableNode: ASTableNode, willBeginBatchFetchWith context: ASBatchContext) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                context.completeBatchFetching(true)
                return
            }
            self.lastBatchFetchRequestedCount = self.records.count
            self.loadMoreIfNeeded()
            context.completeBatchFetching(true)
        }
    }
}
