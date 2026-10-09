//
//  UserDiscussionsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import AsyncDisplayKit
import UIKit

@MainActor
final class UserDiscussionsViewController: UIViewController {
    private let tableNode = ASTableNode(style: .plain)
    private let refreshControl = UIRefreshControl()
    private let footerView = UserContentFooterView()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "user-discussions-error-view")
    private let client: NodeSeekUserContentClient
    private let currentAccountStore: CurrentAccountStore
    private let visitedStore: VisitedPostStoreProtocol
    private let requestedUserID: Int?
    private var records: [UserDiscussionRecord] = []
    private var resolvedPostSummaries: [Int: PostSummary] = [:]
    private var summaryRefreshGeneration = 0
    private var displayMode: UserContentDisplayMode = .content
    private var uid: Int?
    private var nextPage = 2
    private var hasMorePages = true
    private var isLoadingFirstPage = false
    private var isRefreshing = false
    private var isLoadingMore = false
    private var lastBatchFetchRequestedCount: Int?
    private var shouldStreamContentAppearance = false
    private var allowsEditing = false
    private var currentAccount: AccountResponse?
    private let skeletonRowCount = 9
    var onSelectPost: ((PostSummary, Int, String?) -> Void)?

    init(
        userID: Int? = nil,
        authorName _: String? = nil,
        avatarURL _: URL? = nil,
        client: NodeSeekUserContentClient? = nil,
        currentAccountStore: CurrentAccountStore = .shared,
        visitedStore: VisitedPostStoreProtocol = VisitedPostStore.shared
    ) {
        requestedUserID = userID
        self.client = client ?? NodeSeekUserContentClient()
        self.currentAccountStore = currentAccountStore
        self.visitedStore = visitedStore
        super.init(nibName: nil, bundle: nil)
        title = "主题帖"
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
        tableNode.view.allowsSelection = false
        tableNode.view.tableFooterView = footerView
        tableNode.view.backgroundColor = .systemBackground
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableNode.view.refreshControl = refreshControl
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
        isRefreshing = false
        isLoadingMore = false
        hasMorePages = true
        nextPage = 2
        lastBatchFetchRequestedCount = nil
        showSkeleton()

        Task { [weak self] in
            guard let self else { return }
            do {
                let uid = try await resolveUID()
                let loaded = try await client.loadDiscussions(uid: uid, page: 1)
                self.uid = uid
                self.currentAccount = await self.currentAccountStore.snapshot()?.account
                self.allowsEditing = self.currentAccount?.nodeSeekUID == uid
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
                let loaded = try await client.loadDiscussions(uid: uid, page: page)
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

    private func finishFirstPage(records: [UserDiscussionRecord]) {
        self.records = records
        resolvedPostSummaries.removeAll()
        displayMode = .content
        isLoadingFirstPage = false
        isRefreshing = false
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

    private func finishLoadMore(records loaded: [UserDiscussionRecord], page: Int) {
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
        isRefreshing = false
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

    private func openRecord(_ record: UserDiscussionRecord) {
        if allowsEditing, let navigationController {
            navigationController.pushViewController(
                PostDetailRouter.createModule(
                    post: postSummary(for: record),
                    page: 1,
                    showsDiscussionEditAction: true
                ),
                animated: true
            )
            return
        }
        onSelectPost?(postSummary(for: record), 1, nil)
    }

    private func openProfile(userID: Int?) {
        guard let userID, userID > 0 else { return }
        navigationController?.pushViewController(ProfileTabViewController(userID: userID), animated: true)
    }

    private func openLatestReply(for record: UserDiscussionRecord) {
        navigationController?.pushViewController(
            PostDetailRouter.createModule(
                post: postSummary(for: record),
                page: 1,
                opensLatestComment: true
            ),
            animated: true
        )
    }


    private func postSummary(for record: UserDiscussionRecord) -> PostSummary {
        let resolvedSummary = resolvedPostSummaries[record.postID]
        let resolvedAuthorName = (resolvedSummary?.authorName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cachedStatistics = visitedStore.record(forPostID: "\(record.postID)")
        let recordAuthorName = record.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackAccount = allowsEditing ? currentAccount : nil
        let fallbackAuthorName = recordAuthorName.isEmpty ? (fallbackAccount?.displayName ?? "") : recordAuthorName

        return PostSummary(
            id: "\(record.postID)",
            title: record.title,
            url: NodeSeekSite.postURL(id: "\(record.postID)", page: 1),
            authorName: resolvedAuthorName.isEmpty ? fallbackAuthorName : resolvedAuthorName,
            nodeName: resolvedSummary?.nodeName ?? record.nodeName,
            replyCount: max(max(resolvedSummary?.replyCount ?? 0, record.replyCount ?? 0), cachedStatistics?.replyCount ?? 0),
            viewCount: max(max(resolvedSummary?.viewCount ?? 0, record.viewCount ?? 0), cachedStatistics?.viewCount ?? 0),
            createdAtText: record.createdAtText,
            lastActivityText: resolvedSummary?.lastActivityText ?? record.lastActivityText,
            avatarURL: resolvedSummary?.avatarURL ?? record.avatarURL ?? fallbackAccount?.avatarURL,
            authorProfileURL: resolvedSummary?.authorProfileURL ?? fallbackAccount?.profileURL,
            authorBadgeTexts: resolvedSummary?.authorBadgeTexts ?? []
        )
    }

    private func refreshPostSummaries(for candidates: [UserDiscussionRecord]) {
        guard candidates.isEmpty == false else { return }
        summaryRefreshGeneration += 1
        let generation = summaryRefreshGeneration
        var cachedViewCounts: [Int: Int] = [:]
        var cachedReplyCounts: [Int: Int] = [:]
        for record in candidates {
            let cached = visitedStore.record(forPostID: "\(record.postID)")
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

extension UserDiscussionsViewController: ASTableDataSource {
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
                UserDiscussionCellNode(
                    record: record,
                    post: post,
                    onOpenPost: { [weak self] in self?.openRecord(record) }
                )
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

extension UserDiscussionsViewController: ASTableDelegate {
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

enum UserContentViewError: LocalizedError {
    case missingUID

    var errorDescription: String? {
        "未获取到账号 UID，请重新登录后再试"
    }
}
