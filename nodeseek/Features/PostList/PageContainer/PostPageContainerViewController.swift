//
//  PostPageContainerViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

protocol PostPageContainerViewControllerDelegate: AnyObject {
    func postPageContainerViewController(_ viewController: PostPageContainerViewController, didSelectPost post: PostSummary, category: PostListCategoryItem)
    func postPageContainerViewController(_ viewController: PostPageContainerViewController, didChangeSortMode sortMode: PostListSortMode, category: PostListCategoryItem)
    func postPageContainerViewController(_ viewController: PostPageContainerViewController, didScrollTo category: PostListCategoryItem)
    func postPageContainerViewController(_ viewController: PostPageContainerViewController, didLoadFirstPageFor category: PostListCategoryItem)
    func postPageContainerViewController(_ viewController: PostPageContainerViewController, didFailInitialLoadFor category: PostListCategoryItem)
    func postPageContainerViewControllerDidRequestLeadingSideMenu(_ viewController: PostPageContainerViewController)
}

final class PostPageContainerViewController: UIPageViewController {

    weak var eventDelegate: PostPageContainerViewControllerDelegate?

    var categories: [PostListCategoryItem] = []
    var hostViewControllers: [PostListCategoryItem: PostTextureListHostViewController] = [:]
    private(set) var currentCategory: PostListCategoryItem?
    weak var pagingScrollView: UIScrollView?
    var maximumLeadingBoundaryPullDistance: CGFloat = 0
    private let visitedStore: VisitedPostStoreProtocol
    private var isPagingTransitioning = false
    private var pendingCategorySelection: (category: PostListCategoryItem, animated: Bool, notifyDelegate: Bool)?
    private var needsVisiblePageRecovery = false

    init(
        visitedStore: VisitedPostStoreProtocol
    ) {
        self.visitedStore = visitedStore
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 0]
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupPaging()
        showCurrentOrFirstPage()
    }

    func configure(categories: [PostListCategoryItem]) {
        guard self.categories != categories else { return }
        self.categories = categories

        var newHosts: [PostListCategoryItem: PostTextureListHostViewController] = [:]
        for category in categories {
            if let existing = hostViewControllers[category] {
                newHosts[category] = existing
            } else {
                let host = PostTextureListHostRouter.createModule(
                    category: category,
                    visitedStore: visitedStore,
                    delegate: self
                )
                newHosts[category] = host
            }
        }
        hostViewControllers = newHosts

        if let current = currentCategory, !categories.contains(current) {
            currentCategory = nil
        }
        showCurrentOrFirstPage()
    }

    func setCurrentCategory(_ category: PostListCategoryItem, animated: Bool) {
        guard categories.contains(category) else { return }
        setCurrentCategory(category, animated: animated, notifyDelegate: false)
    }

    func sortMode(for category: PostListCategoryItem) -> PostListSortMode {
        hostViewControllers[category]?.currentSortMode ?? .replyTime
    }

    @discardableResult
    func toggleSortMode(for category: PostListCategoryItem) -> PostListSortMode {
        guard let host = hostViewControllers[category] else { return .replyTime }
        return host.toggleSortMode()
    }

    func reloadFirstPage(for category: PostListCategoryItem) {
        hostViewControllers[category]?.reloadFirstPage()
    }

    func refreshFirstPageKeepingContent(for category: PostListCategoryItem) {
        hostViewControllers[category]?.refreshFirstPageKeepingContent()
    }

    func scrollToTop(for category: PostListCategoryItem, animated: Bool) {
        hostViewControllers[category]?.scrollToTop(animated: animated)
    }

    func refreshVisibleAppearanceForCurrentTraits() {
        hostViewControllers.values.forEach { $0.refreshVisibleAppearanceForCurrentTraits() }
    }

    func replayStreamAppearanceIfNeeded() {
        guard let category = currentCategory ?? categories.first else { return }
        hostViewControllers[category]?.replayStreamAppearanceIfNeeded()
    }

    func recoverVisiblePageIfNeeded() {
        guard categories.isEmpty == false else { return }
        guard isPagingTransitioning == false else {
            // 页面正在由手势接管时不能再次 setViewControllers。等分页器完成后，
            // 使用它最终实际展示的控制器恢复，防止出现标题与内容页不同步的白屏。
            needsVisiblePageRecovery = true
            return
        }
        if let visibleHost = viewControllers?.first as? PostTextureListHostViewController,
           categories.contains(visibleHost.category) {
            currentCategory = visibleHost.category
            visibleHost.ensureFirstPageLoaded()
        } else if let category = currentCategory ?? categories.first {
            setCurrentCategory(category, animated: false, notifyDelegate: false)
        }
        view.setNeedsLayout()
    }

    private func setupPaging() {
        dataSource = self
        delegate = self

        if let pagingScrollView = view.subviews.compactMap({ $0 as? UIScrollView }).first {
            pagingScrollView.isDirectionalLockEnabled = true
            pagingScrollView.showsHorizontalScrollIndicator = false
            installLeadingBoundaryPanListener(on: pagingScrollView)
        }
    }

    private func showCurrentOrFirstPage() {
        guard let category = currentCategory ?? categories.first else { return }
        setCurrentCategory(category, animated: false, notifyDelegate: false)
    }

    private func setCurrentCategory(_ category: PostListCategoryItem, animated: Bool, notifyDelegate: Bool) {
        guard let targetVC = hostViewControllers[category] else { return }
        guard isPagingTransitioning == false else {
            pendingCategorySelection = (category, animated, notifyDelegate)
            return
        }
        // 先创建目标页面的骨架，页面切换不再依赖异步首屏请求的完成时机。
        targetVC.ensureFirstPageLoaded()
        if viewControllers?.first === targetVC {
            currentCategory = category
            return
        }
        pagingScrollView?.isScrollEnabled = true

        let visibleCategory = (viewControllers?.first as? PostTextureListHostViewController)?.category ?? currentCategory
        let direction: UIPageViewController.NavigationDirection = {
            guard let current = visibleCategory,
                  let fromIndex = categories.firstIndex(of: current),
                  let toIndex = categories.firstIndex(of: category) else {
                return .forward
            }
            return toIndex >= fromIndex ? .forward : .reverse
        }()

        currentCategory = category
        isPagingTransitioning = animated
        pagingScrollView?.isScrollEnabled = animated == false
        setViewControllers([targetVC], direction: direction, animated: animated) { [weak self] completed in
            guard let self else { return }
            self.isPagingTransitioning = false
            self.pagingScrollView?.isScrollEnabled = true
            if let visibleHost = self.viewControllers?.first as? PostTextureListHostViewController {
                // 转场若被新的手势打断，状态必须回到分页器实际显示的页面。
                self.currentCategory = visibleHost.category
            }
            if notifyDelegate, completed || !animated {
                self.eventDelegate?.postPageContainerViewController(
                    self,
                    didScrollTo: self.currentCategory ?? category
                )
            }
            self.applyPendingCategorySelectionIfNeeded()
            self.recoverVisiblePageAfterPagingIfNeeded()
        }
    }

    func updateCurrentCategoryAfterPaging(_ category: PostListCategoryItem) {
        currentCategory = category
        pagingScrollView?.isScrollEnabled = true
    }

    func beginPagingTransition() {
        isPagingTransitioning = true
    }

    func finishPagingTransition() {
        isPagingTransitioning = false
        pagingScrollView?.isScrollEnabled = true
        if let visibleHost = viewControllers?.first as? PostTextureListHostViewController,
           categories.contains(visibleHost.category) {
            currentCategory = visibleHost.category
        }
        applyPendingCategorySelectionIfNeeded()
        recoverVisiblePageAfterPagingIfNeeded()
    }

    private func applyPendingCategorySelectionIfNeeded() {
        guard let pendingCategorySelection else { return }
        self.pendingCategorySelection = nil
        setCurrentCategory(
            pendingCategorySelection.category,
            animated: pendingCategorySelection.animated,
            notifyDelegate: pendingCategorySelection.notifyDelegate
        )
    }

    private func recoverVisiblePageAfterPagingIfNeeded() {
        guard needsVisiblePageRecovery else { return }
        needsVisiblePageRecovery = false
        DispatchQueue.main.async { [weak self] in
            self?.recoverVisiblePageIfNeeded()
        }
    }
}

extension PostPageContainerViewController: PostTextureListHostPresenterDelegate {
    func postTextureListHostDidSelectPost(_ post: PostSummary, category: PostListCategoryItem) {
        eventDelegate?.postPageContainerViewController(self, didSelectPost: post, category: category)
    }

    func postTextureListHostDidChangeSortMode(_ sortMode: PostListSortMode, category: PostListCategoryItem) {
        eventDelegate?.postPageContainerViewController(self, didChangeSortMode: sortMode, category: category)
    }

    func postTextureListHostDidLoadFirstPage(category: PostListCategoryItem) {
        eventDelegate?.postPageContainerViewController(self, didLoadFirstPageFor: category)
    }

    func postTextureListHostDidFailInitialLoad(category: PostListCategoryItem) {
        eventDelegate?.postPageContainerViewController(self, didFailInitialLoadFor: category)
    }
}
