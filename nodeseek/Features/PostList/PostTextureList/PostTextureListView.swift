//
//  PostTextureListView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import UIKit
import Foundation

protocol PostTextureListViewDelegate: AnyObject {
    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int)
    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView)
    func postTextureListViewDidRequestFirstPageRetry(_ textureListView: PostTextureListView)
    func postTextureListView(_ textureListView: PostTextureListView, didApproachBottomAt index: Int, totalCount: Int)
}

final class PostTextureListView: UIView {
    private enum DisplayMode {
        case content
        case skeleton
        case firstPageError
    }

    weak var delegate: PostTextureListViewDelegate?
    var isSpecialFollow = false

    private let tableNode = ASTableNode(style: .plain)
    private let refreshControl = UIRefreshControl()
    private var displayMode: DisplayMode = .content
    private var items: [PostListItem] = []
    private let minimumSkeletonRowCount = 8
    private var estimatedSkeletonRowHeight: CGFloat {
        PostListCellStyle.Avatar.skeletonSize
            + PostListCellStyle.Layout.verticalContentInset * 2
    }
    private let leadingScreensForBatching: CGFloat = 2.0
    private var skeletonRowCount: Int = 8
    private var lastBatchFetchRequestedItemCount: Int?
    /// 流式浮现参数集中一处，调手感只改这里。
    private enum StreamAppearance {
        static let rowStaggerDelay: TimeInterval = 0.035
        static let duration: TimeInterval = 0.42
        static let springDamping: CGFloat = 0.86
        static let springVelocity: CGFloat = 0.4
        static let offsetY: CGFloat = 16
        static let initialScale: CGFloat = 0.98
        static let maximumInitialRowCount = 24
    }
    private var pendingStreamRowIndexes = Set<Int>()
    /// token → 动画器：计数天然精确，取消时也能逐个平滑收尾。
    private var activeStreamAnimators: [Int: UIViewPropertyAnimator] = [:]
    private var nextStreamAnimationToken = 0
    private var isPostSelectionLocked = false
    private var selectionUnlockWorkItem: DispatchWorkItem?

    private let loadMoreIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let errorTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "加载失败"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let errorMessageLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var retryButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "重试"
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
        let button = UIButton(type: .system)
        button.configuration = configuration
        button.accessibilityIdentifier = "post-list-first-page-retry-button"
        button.addTarget(self, action: #selector(retryFirstPageTapped), for: .touchUpInside)
        return button
    }()

    private lazy var errorStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [errorTitleLabel, errorMessageLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.isHidden = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.accessibilityIdentifier = "post-list-first-page-error"
        return stack
    }()

    private lazy var loadMoreContainer: UIView = {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 56))
        container.addSubview(loadMoreIndicator)
        NSLayoutConstraint.activate([
            loadMoreIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadMoreIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        selectionUnlockWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func setItems(_ items: [PostListItem]) {
        hideErrorView()
        if self.items.count != items.count {
            lastBatchFetchRequestedItemCount = nil
        }
        if displayMode == .content, self.items == items {
            // 刷新结果可能与当前数据完全相同，仍需重播流式动画，不能直接跳过。
            replayStreamAppearance()
            return
        }
        if displayMode != .content {
            self.items = items
            displayMode = .content
            reloadDataForStreamAppearance()
            return
        }

        if let appendIndexPaths = makeAppendIndexPaths(from: self.items, to: items) {
            self.items = items
            // 分页追加发生在滚动底部，关闭 row 插入动画可以避免 Texture 调整 contentOffset 时牵动上方内容。
            tableNode.performBatch(animated: false, updates: { [weak self] in
                self?.tableNode.insertRows(at: appendIndexPaths, with: .none)
            })
            return
        }

        self.items = items
        reloadDataForStreamAppearance()
    }

    /// 同一批帖子只更新内容，保留已经挂载的 Texture 节点和当前滚动位置。
    /// 历史列表的统计补全会频繁回写，若每次都 reloadData，切回 tab 时容易出现瞬间空白。
    func replaceItemsPreservingViewport(_ items: [PostListItem]) {
        hideErrorView()
        guard displayMode == .content else {
            setItems(items)
            return
        }

        let hasSameRows = self.items.count == items.count
            && zip(self.items, items).allSatisfy { $0.post.id == $1.post.id }
        guard hasSameRows else {
            setItems(items)
            return
        }
        guard self.items != items else {
            replayStreamAppearance()
            return
        }

        self.items = items
        let rows = (0..<items.count).map { IndexPath(row: $0, section: 0) }
        guard rows.isEmpty == false else { return }
        tableNode.performBatch(animated: false) { [weak self] in
            self?.tableNode.reloadRows(at: rows, with: .none)
        }
    }

    func updateVisitedState(at index: Int, isVisited: Bool) {
        guard displayMode == .content else { return }
        guard items.indices.contains(index) else { return }
        let existing = items[index]
        guard existing.isVisited != isVisited else { return }
        items[index] = PostListItem(post: existing.post, isVisited: isVisited)
        tableNode.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
    }

    func showLoadingSkeleton() {
        hideErrorView()
        guard displayMode != .skeleton else { return }
        cancelStreamAppearance()
        displayMode = .skeleton
        lastBatchFetchRequestedItemCount = nil
        skeletonRowCount = currentSkeletonRowCount()
        hideLoadingMore()
        tableNode.reloadData()
    }

    func hideLoadingSkeleton() {
        guard displayMode == .skeleton else { return }
        displayMode = .content
        tableNode.reloadData()
    }

    func showFirstPageError(message: String) {
        cancelStreamAppearance()
        displayMode = .firstPageError
        items = []
        lastBatchFetchRequestedItemCount = nil
        hideLoadingMore()
        hideRefreshing()
        errorMessageLabel.text = message
        errorStackView.isHidden = false
        tableNode.reloadData()
    }

    func hideFirstPageError() {
        guard displayMode == .firstPageError else {
            hideErrorView()
            return
        }
        displayMode = .content
        hideErrorView()
        tableNode.reloadData()
    }

    func showLoadingMore() {
        loadMoreIndicator.startAnimating()
    }

    func hideLoadingMore() {
        loadMoreIndicator.stopAnimating()
        lastBatchFetchRequestedItemCount = nil
    }

    func hideRefreshing() {
        refreshControl.endRefreshing()
    }

    func scrollToTop(animated: Bool) {
        tableNode.setContentOffset(.zero, animated: animated)
    }

    func refreshVisibleAppearanceForCurrentTraits() {
        tableNode.visibleNodes.forEach { node in
            (node as? ThemeRefreshableNode)?.refreshAppearanceForCurrentTraits()
        }
    }

    private func setupUI() {
        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.leadingScreensForBatching = leadingScreensForBatching
        tableNode.view.separatorStyle = .singleLine
        tableNode.view.showsVerticalScrollIndicator = true
        tableNode.view.tableFooterView = loadMoreContainer
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        tableNode.view.refreshControl = refreshControl
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appTextSizeDidChange(_:)),
            name: AppTextSizeSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(specialFollowKeywordsDidChange(_:)),
            name: SpecialFollowKeywordStore.didChangeNotification,
            object: SpecialFollowKeywordStore.shared
        )

        addSubview(tableNode.view)
        addSubview(errorStackView)
        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: bottomAnchor),

            errorStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            errorStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32)
        ])
    }

    private func hideErrorView() {
        errorStackView.isHidden = true
    }

    /// 板块/tab 切换后重播当前可见行。整表不再先隐藏，避免 Texture 异步提交时闪白。
    func replayStreamAppearance() {
        guard displayMode == .content, items.isEmpty == false else { return }
        streamVisibleRowsIfNeeded()
        guard hasPendingStreamAppearance == false else { return }
        let cells = tableNode.view.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
        guard cells.isEmpty == false else {
            prepareIncomingStreamAppearance()
            return
        }
        animateStreamAppearance(cells)
    }

    /// 列表内容到达时只登记首屏行，等 Texture 发出 willDisplay 回调再逐行播放。
    /// 即使数据在首页还被其它功能页遮挡时到达，也不会丢失流式动画。
    private func reloadDataForStreamAppearance() {
        prepareIncomingStreamAppearance()
        tableNode.reloadData()
    }

    private func prepareIncomingStreamAppearance() {
        stopAllStreamAnimators()
        pendingStreamRowIndexes = Set(0..<min(items.count, StreamAppearance.maximumInitialRowCount))
    }

    private var hasPendingStreamAppearance: Bool {
        pendingStreamRowIndexes.isEmpty == false || activeStreamAnimators.isEmpty == false
    }

    private var isReadyToStreamAppearance: Bool {
        guard window != nil else { return false }
        var candidate: UIView? = self
        while let view = candidate {
            guard view.isHidden == false, view.alpha > 0.01 else { return false }
            candidate = view.superview
        }
        return true
    }

    private func streamVisibleRowsIfNeeded() {
        guard isReadyToStreamAppearance else { return }
        for cell in tableNode.view.visibleCells.sorted(by: { $0.frame.minY < $1.frame.minY }) {
            guard let indexPath = tableNode.view.indexPath(for: cell) else { continue }
            streamRowIfNeeded(cell, at: indexPath.row)
        }
        finalizeIncomingStreamAppearanceIfViewportIsCovered()
    }

    private func streamRowIfNeeded(_ cell: UIView, at index: Int) {
        guard isReadyToStreamAppearance,
              pendingStreamRowIndexes.remove(index) != nil
        else {
            return
        }
        animateStreamAppearance(cell, sequence: index)
        finalizeIncomingStreamAppearanceIfViewportIsCovered()
    }

    private func animateStreamAppearance(_ cells: [UITableViewCell]) {
        for (index, cell) in cells.enumerated() {
            animateStreamAppearance(cell, sequence: index)
        }
    }

    /// 登记即进入初始态、按延迟启动动画：cell 不会先完整可见再瞬间消失，避免闪烁。
    private func animateStreamAppearance(_ cell: UIView, sequence: Int) {
        cell.layer.removeAllAnimations()
        cell.alpha = 0
        cell.transform = CGAffineTransform(translationX: 0, y: StreamAppearance.offsetY)
            .scaledBy(x: StreamAppearance.initialScale, y: StreamAppearance.initialScale)

        let animator = UIViewPropertyAnimator(
            duration: StreamAppearance.duration,
            timingParameters: UISpringTimingParameters(
                dampingRatio: StreamAppearance.springDamping,
                initialVelocity: CGVector(dx: 0, dy: StreamAppearance.springVelocity)
            )
        )
        animator.addAnimations { [weak cell] in
            cell?.alpha = 1
            cell?.transform = .identity
        }
        let token = nextStreamAnimationToken
        nextStreamAnimationToken += 1
        animator.addCompletion { [weak self] _ in
            self?.activeStreamAnimators.removeValue(forKey: token)
        }
        activeStreamAnimators[token] = animator
        animator.startAnimation(afterDelay: Double(sequence) * StreamAppearance.rowStaggerDelay)
    }

    /// Texture 可能在首行显示后才提交底部行。等真实可见行覆盖到视口底部再结束首屏流式，
    /// 避免固定延时让下半屏错过动画。
    private func finalizeIncomingStreamAppearanceIfViewportIsCovered() {
        guard pendingStreamRowIndexes.isEmpty == false,
              isReadyToStreamAppearance else {
            return
        }

        let tableView = tableNode.view
        let visibleBottom = tableView.bounds.maxY - tableView.adjustedContentInset.bottom
        guard visibleBottom > tableView.bounds.minY else { return }

        let lastVisibleCellBottom = tableView.visibleCells.map(\.frame.maxY).max() ?? 0
        let contentEndsInsideViewport = tableView.contentSize.height
            <= visibleBottom + tableView.adjustedContentInset.bottom + 1
        guard contentEndsInsideViewport || lastVisibleCellBottom >= visibleBottom - 1 else {
            return
        }
        pendingStreamRowIndexes.removeAll()
    }

    private func cancelStreamAppearance() {
        stopAllStreamAnimators()
        pendingStreamRowIndexes.removeAll()
        for cell in tableNode.view.visibleCells {
            cell.layer.removeAllAnimations()
            cell.alpha = 1
            cell.transform = .identity
        }
    }

    /// stop 之后必须 finish 才能释放；已自然结束的动画器停在 inactive，按状态跳过。
    private func stopAllStreamAnimators() {
        let animators = Array(activeStreamAnimators.values)
        activeStreamAnimators.removeAll()
        for animator in animators {
            animator.stopAnimation(true)
            if animator.state == .stopped {
                animator.finishAnimation(at: .current)
            }
        }
    }

    private func makeAppendIndexPaths(from oldItems: [PostListItem], to newItems: [PostListItem]) -> [IndexPath]? {
        guard newItems.count > oldItems.count else { return nil }
        guard !oldItems.isEmpty else { return nil }

        for index in oldItems.indices where oldItems[index].post.id != newItems[index].post.id {
            return nil
        }

        return (oldItems.count..<newItems.count).map { IndexPath(row: $0, section: 0) }
    }

    @objc private func handlePullToRefresh() {
        delegate?.postTextureListViewDidRequestRefresh(self)
    }

    @objc private func appTextSizeDidChange(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.appTextSizeDidChange(notification)
            }
            return
        }
        guard displayMode == .content else { return }
        tableNode.reloadData()
    }

    @objc private func specialFollowKeywordsDidChange(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.specialFollowKeywordsDidChange(notification)
            }
            return
        }
        guard displayMode == .content else { return }
        tableNode.reloadData()
    }

    @objc private func retryFirstPageTapped() {
        delegate?.postTextureListViewDidRequestFirstPageRetry(self)
    }

    private func lockPostSelection() {
        isPostSelectionLocked = true
        selectionUnlockWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.isPostSelectionLocked = false
        }
        selectionUnlockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        streamVisibleRowsIfNeeded()
        guard displayMode == .skeleton else { return }
        let targetRowCount = currentSkeletonRowCount()
        guard targetRowCount != skeletonRowCount else { return }
        skeletonRowCount = targetRowCount
        tableNode.reloadData()
    }

    private func currentSkeletonRowCount() -> Int {
        let visibleHeight = max(bounds.height, tableNode.view.bounds.height)
        guard visibleHeight > 0 else { return minimumSkeletonRowCount }
        let visibleRows = Int(ceil(visibleHeight / estimatedSkeletonRowHeight)) + 1
        return max(minimumSkeletonRowCount, visibleRows)
    }
}

extension PostTextureListView: ASTableDataSource {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        switch displayMode {
        case .content:
            return items.count
        case .skeleton:
            return skeletonRowCount
        case .firstPageError:
            return 0
        }
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        switch displayMode {
        case .content:
            let item = items[indexPath.row]
            let isSpecialFollow = self.isSpecialFollow
            return {
                PostSummaryCellNode(item: item, isSpecialFollow: isSpecialFollow)
            }
        case .skeleton:
            return {
                PostSummarySkeletonCellNode()
            }
        case .firstPageError:
            return {
                ASCellNode()
            }
        }
    }
}

extension PostTextureListView: ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, willDisplayRowWith node: ASCellNode) {
        guard displayMode == .content,
              let indexPath = tableNode.indexPath(for: node)
        else {
            return
        }
        if pendingStreamRowIndexes.contains(indexPath.row) {
            streamRowIfNeeded(node.view, at: indexPath.row)
        } else if node.view.alpha != 1 || node.view.transform != .identity {
            // 复用的 cell 可能残留流式初始态（透明+位移），进屏前恢复默认外观。
            node.view.layer.removeAllAnimations()
            node.view.alpha = 1
            node.view.transform = .identity
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content, isPostSelectionLocked == false else {
            return
        }
        tableNode.deselectRow(at: indexPath, animated: true)
        lockPostSelection()
        delegate?.postTextureListView(self, didSelectPostAt: indexPath.row)
    }

    func shouldBatchFetch(for tableNode: ASTableNode) -> Bool {
        canRequestBatchFetch()
    }

    func tableNode(_ tableNode: ASTableNode, willBeginBatchFetchWith context: ASBatchContext) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                context.completeBatchFetching(true)
                return
            }

            guard self.canRequestBatchFetch() else {
                AppLog.debug(.postList, "忽略 Texture 分页触发: itemCount=\(self.items.count), lastRequested=\(self.lastBatchFetchRequestedItemCount ?? -1)")
                context.completeBatchFetching(true)
                return
            }

            let totalCount = self.items.count
            self.lastBatchFetchRequestedItemCount = totalCount
            AppLog.info(.postList, "Texture 提前触发帖子列表分页: itemCount=\(totalCount), leadingScreens=\(self.leadingScreensForBatching)")
            self.delegate?.postTextureListView(
                self,
                didApproachBottomAt: max(totalCount - 1, 0),
                totalCount: totalCount
            )
            context.completeBatchFetching(true)
        }
    }

    private func canRequestBatchFetch() -> Bool {
        guard displayMode == .content else { return false }
        guard !items.isEmpty else { return false }
        guard lastBatchFetchRequestedItemCount != items.count else { return false }
        return true
    }
}
