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
    /// 已经在补元数据的行，避免同一行被 willDisplay 反复触发。
    private var summaryRequests: Set<Int> = []
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
    }

    private func showSkeleton() {
        displayMode = .skeleton
        records = []
        resolvedPostSummaries.removeAll()
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
        let cachedStatistics = visitedStore.record(forPostID: "\(record.postID)")
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

    /// 只给滚到眼前的行补元数据。
    ///
    /// 实测收藏接口一行只有 post_id / rank / title 三个键，浏览数、评论数、
    /// 作者、头像、板块名一概没有，所以每行都必须抓一次整页详情才能显示东西。
    /// 原来进页面就把当页记录一次性全丢进去：真机日志里 63 个帖子、73 次请求，
    /// 排速队列堆到 18 深、单条最长等 40.8 秒。改成按需，一屏也就八行。
    private func requestSummaryIfNeeded(for record: UserCollectionRecord) {
        guard displayMode == .content,
              resolvedPostSummaries[record.postID] == nil,
              summaryRequests.contains(record.postID) == false else { return }
        summaryRequests.insert(record.postID)

        let cached = visitedStore.record(forPostID: "\(record.postID)")
        let fallbackViewCount = max(record.viewCount ?? 0, cached?.viewCount ?? 0)
        let fallbackReplyCount = max(record.replyCount ?? 0, cached?.replyCount ?? 0)

        Task { [weak self] in
            let summary = await PostSummaryResolver.shared.resolveHistoryMetadata(
                postID: "\(record.postID)",
                title: record.title,
                fallbackViewCount: fallbackViewCount,
                fallbackReplyCount: fallbackReplyCount
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.summaryRequests.remove(record.postID)
                guard self.displayMode == .content, let summary else { return }
                self.resolvedPostSummaries[record.postID] = summary
                guard let row = self.records.firstIndex(where: { $0.postID == record.postID }) else { return }
                self.tableNode.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
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
            // 行即将生成才去补元数据：收藏接口一行只给 post_id/rank/title，
            // 每行都得抓一次整页详情，一次性铺开会把排速队列堆到十几层。
            // 异步一跳，避免在 Texture 生成 cell 的过程中改数据源。
            DispatchQueue.main.async { [weak self] in
                self?.requestSummaryIfNeeded(for: record)
            }
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
