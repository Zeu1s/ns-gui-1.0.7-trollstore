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
    /// 上一轮数据快照，供差分更新识别“变化的已有行”。
    private var previousItems: [PostListItem] = []
    private let minimumSkeletonRowCount = 8
    private var estimatedSkeletonRowHeight: CGFloat {
        PostListCellStyle.Avatar.skeletonSize
            + PostListCellStyle.Layout.verticalContentInset * 2
    }
    private let leadingScreensForBatching: CGFloat = 2.0
    private var skeletonRowCount: Int = 8
    private var lastBatchFetchRequestedItemCount: Int?
    /// 流式浮现的全部状态（pending 行、动画器）收在控制器里，视图只转发时机。
    private lazy var streamController = PostListStreamAppearanceController(
        hostView: self,
        tableView: tableNode.view
    )
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
        if displayMode == .content {
            guard self.items != items else {
                // 刷新结果与当前完全一致：原地静默，不做任何视觉动作。
                return
            }
            applyDiffedUpdate(items)
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

    /// 方案乙：差分刷新。识别新出现的帖子行并带渐隐新帖标记，其余行原位刷新，
    /// 全程整表不隐藏、不重播流式，滚动位置由 Texture 行级更新保持。
    private func applyDiffedUpdate(_ newItems: [PostListItem]) {
        let oldIDs = Set(self.items.map(\.post.id))
        let insertedIndexes = newItems.enumerated().compactMap { index, item in
            oldIDs.contains(item.post.id) ? nil : index
        }
        // 防御：插入路径只对“纯追加且索引严格递增对齐”的换血安全。
        // 任何删除/重排/换血（插入数 != 总数差）都会造成 datasource 与
        // batch updates 数量不一致（曾以 ASCollectionInvalidUpdateException 崩溃），
        // 一律退回整表 reload。
        let isPureAppend = newItems.count > self.items.count
            && insertedIndexes.count == newItems.count - self.items.count
            && newItems[newItems.count - insertedIndexes.count...].allSatisfy { item in
                oldIDs.contains(item.post.id) == false
            }
        guard isPureAppend else {
            self.items = newItems
            reloadDataForStreamAppearance()
            return
        }
        // 新帖过多（如板块切换后的整体换血）时退回整表，不逐行打标记。
        let shouldMarkNewRows = insertedIndexes.count <= Self.newArrivalMarkLimit

        // 头部被顶走的行数：Texture 不做自动 offset 补偿，插入在可视区上方时补偿避免跳动。
        let insertedAboveVisible = insertedIndexes.filter { $0 < firstVisibleRowIndex() }.count

        self.items = newItems
        if insertedIndexes.isEmpty {
            tableNode.performBatch(animated: false) { [weak self] in
                guard let self else { return }
                let rows = (0..<newItems.count).map { IndexPath(row: $0, section: 0) }
                self.tableNode.reloadRows(at: rows, with: .none)
            }
            return
        }

        if insertedAboveVisible > 0 {
            let targetOffset = CGPoint(
                x: tableNode.view.contentOffset.x,
                y: tableNode.view.contentOffset.y + CGFloat(insertedAboveVisible) * Self.estimatedPostRowHeight
            )
            tableNode.view.setContentOffset(targetOffset, animated: false)
        }

        tableNode.performBatch(animated: false, updates: { [weak self] in
            guard let self else { return }
            self.tableNode.insertRows(
                at: insertedIndexes.map { IndexPath(row: $0, section: 0) },
                with: .none
            )
            let changedExistingRows = (0..<newItems.count).filter { index in
                insertedIndexes.contains(index) == false
                    && index < self.items.count
                    && index < self.previousItems.count
                    && self.previousItems[index] != newItems[index]
            }
            if changedExistingRows.isEmpty == false {
                self.tableNode.reloadRows(
                    at: changedExistingRows.map { IndexPath(row: $0, section: 0) },
                    with: .none
                )
            }
        }, completion: { [weak self] _ in
            guard let self, shouldMarkNewRows else { return }
            self.presentNewArrivalMarks(at: insertedIndexes)
        })
        self.previousItems = newItems
    }

    private func presentNewArrivalMarks(at indexes: [Int]) {
        for index in indexes {
            guard let node = tableNode.nodeForRow(at: IndexPath(row: index, section: 0)) as? PostSummaryCellNode else {
                continue
            }
            node.presentNewArrivalMark()
        }
    }

    private func firstVisibleRowIndex() -> Int {
        let visible = tableNode.view.indexPathsForVisibleRows
        return visible?.map(\.row).min() ?? 0
    }

    private static let newArrivalMarkLimit = 8
    private static let estimatedPostRowHeight: CGFloat = 96

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
            // 内容完全一致：原地静默。
            return
        }

        self.items = items
        let changedRows = (0..<items.count).filter { index in
            index < self.previousItems.count && self.previousItems[index] != items[index]
        }
        self.previousItems = items
        let rows = (changedRows.isEmpty ? [] : changedRows).map { IndexPath(row: $0, section: 0) }
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
        streamController.cancelAndRestoreVisibleCells()
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
        streamController.cancelAndRestoreVisibleCells()
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
        streamController.layoutDidUpdate()
        guard streamController.isBusy == false else { return }
        streamController.replayVisibleRows(fallbackItemCount: items.count)
    }

    /// 列表内容到达时只登记首屏行，等 Texture 发出 willDisplay 回调再逐行播放。
    /// 即使数据在首页还被其它功能页遮挡时到达，也不会丢失流式动画。
    private func reloadDataForStreamAppearance() {
        streamController.prepareInitialRows(count: items.count)
        tableNode.reloadData()
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
        streamController.layoutDidUpdate()
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
        streamController.registerCellIfNeeded(node.view, rowIndex: indexPath.row)
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
