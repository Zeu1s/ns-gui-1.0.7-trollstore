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
    private let logoPlaceholderView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "SplashLogo"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        imageView.accessibilityLabel = "正在加载"
        return imageView
    }()
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
    private var shouldStreamContentAppearance = false

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
        NotificationCenter.default.removeObserver(self)
    }

    func setItems(_ items: [PostListItem]) {
        hideErrorView()
        let shouldStream = true
        if self.items.count != items.count {
            lastBatchFetchRequestedItemCount = nil
        }
        if displayMode == .content, self.items == items {
            return
        }
        if displayMode != .content {
            self.items = items
            displayMode = .content
            shouldStreamContentAppearance = shouldStream && !items.isEmpty
            tableNode.reloadData()
            streamVisibleRowsIfNeeded()
            fadeOutLogoPlaceholder()
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
        shouldStreamContentAppearance = shouldStream && !items.isEmpty
        tableNode.reloadData()
        streamVisibleRowsIfNeeded()
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
        displayMode = .skeleton
        lastBatchFetchRequestedItemCount = nil
        skeletonRowCount = currentSkeletonRowCount()
        hideLoadingMore()
        tableNode.reloadData()
        showLogoPlaceholder()
    }

    func hideLoadingSkeleton() {
        guard displayMode == .skeleton else { return }
        displayMode = .content
        tableNode.reloadData()
        hideLogoPlaceholder()
    }

    func showFirstPageError(message: String) {
        displayMode = .firstPageError
        items = []
        lastBatchFetchRequestedItemCount = nil
        hideLoadingMore()
        hideRefreshing()
        errorMessageLabel.text = message
        errorStackView.isHidden = false
        tableNode.reloadData()
        hideLogoPlaceholder()
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
        addSubview(logoPlaceholderView)
        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: bottomAnchor),

            errorStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            errorStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),

            logoPlaceholderView.centerXAnchor.constraint(equalTo: centerXAnchor),
            logoPlaceholderView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -24),
            logoPlaceholderView.widthAnchor.constraint(equalToConstant: 120),
            logoPlaceholderView.heightAnchor.constraint(equalToConstant: 120)
        ])
    }

    private func hideErrorView() {
        errorStackView.isHidden = true
    }

    private func showLogoPlaceholder() {
        guard logoPlaceholderView.isHidden else { return }
        logoPlaceholderView.isHidden = false
        logoPlaceholderView.alpha = 0
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.logoPlaceholderView.alpha = 1
        }
    }

    private func hideLogoPlaceholder() {
        logoPlaceholderView.layer.removeAllAnimations()
        logoPlaceholderView.alpha = 0
        logoPlaceholderView.isHidden = true
    }

    private func fadeOutLogoPlaceholder() {
        guard logoPlaceholderView.isHidden == false else { return }
        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.logoPlaceholderView.alpha = 0
        } completion: { _ in
            self.logoPlaceholderView.isHidden = true
        }
    }

    private func streamVisibleRowsIfNeeded() {
        guard shouldStreamContentAppearance else { return }
        // 页面尚未挂到窗口时（例如板块在后台加载完成）不消耗标志，
        // 等 didMoveToWindow 上屏后再触发流式输出，避免切换后直接闪现完整列表。
        guard window != nil else { return }
        shouldStreamContentAppearance = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableNode.view.layoutIfNeeded()
            let cells = self.tableNode.view.visibleCells
                .sorted { $0.frame.minY < $1.frame.minY }
            for (index, cell) in cells.enumerated() {
                cell.alpha = 0
                cell.transform = CGAffineTransform(translationX: 0, y: 10)
                UIView.animate(
                    withDuration: 0.22,
                    delay: Double(index) * 0.03,
                    options: [.curveEaseOut, .allowUserInteraction]
                ) {
                    cell.alpha = 1
                    cell.transform = .identity
                }
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, shouldStreamContentAppearance else { return }
        streamVisibleRowsIfNeeded()
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

    override func layoutSubviews() {
        super.layoutSubviews()
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
    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content else { return }
        tableNode.deselectRow(at: indexPath, animated: true)
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
