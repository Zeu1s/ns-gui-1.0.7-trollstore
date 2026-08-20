//
//  MainTabContainerViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class MainTabContainerViewController: UIViewController {
    private enum Layout {
        static let horizontalInset: CGFloat = 0
        // 底栏总高度固定为 44pt；子视图自己避开底部安全区。
        static let height: CGFloat = 44
    }

    private let containerView = UIView()
    private let bottomNavigationView = PostListBottomNavigationView()
    private var stacks: [PostListBottomNavigationItem: UINavigationController] = [:]
    private var currentItem: PostListBottomNavigationItem = .home
    private weak var visibleStack: UINavigationController?
    private var unreadBadgeVisible = false
    private var displayScaleObserver: NSObjectProtocol?
    private var bottomNavigationHeightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        bottomNavigationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomNavigationView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomNavigationView.topAnchor),

            bottomNavigationView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            bottomNavigationView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            // 底栏本身固定在 Home 指示条上方，内部不再二次扣除安全区。
            bottomNavigationView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        bottomNavigationHeightConstraint = bottomNavigationView.heightAnchor.constraint(
            equalToConstant: bottomNavigationHeight
        )
        bottomNavigationHeightConstraint?.isActive = true

        bottomNavigationView.onItemSelected = { [weak self] item in
            self?.select(item)
        }
        bottomNavigationView.onItemDoubleTapped = { [weak self] item in
            self?.doubleTapRefresh(item)
        }
        bottomNavigationView.setSelectedItem(.home)

        select(.home)
        observeDisplayScaleChanges()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBottomNavigationLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        recoverVisibleContent(in: stack(for: currentItem))
    }

    deinit {
        if let displayScaleObserver {
            NotificationCenter.default.removeObserver(displayScaleObserver)
        }
    }

    private func observeDisplayScaleChanges() {
        displayScaleObserver = NotificationCenter.default.addObserver(
            forName: AppDisplayScaleSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBottomNavigationLayout()
        }
    }

    private func select(_ item: PostListBottomNavigationItem) {
        let reselectedCurrentItem = item == currentItem
        let previousItem = currentItem
        let stack = stack(for: item)
        currentItem = item
        show(stack)
        if item == .history {
            refreshHistoryListIfVisible(in: stack)
        } else if item == .home, previousItem != .home {
            refreshHomeListIfVisible(in: stack)
            recoverVisibleContent(in: stack)
        } else if reselectedCurrentItem {
            resetToTop(of: stack)
        } else {
            recoverVisibleContent(in: stack)
        }
        replayStreamAppearanceIfNeeded(for: item)
        bottomNavigationView.setSelectedItem(item)
        bottomNavigationView.setUnreadMessagesVisible(unreadBadgeVisible)
    }

    private var bottomNavigationHeight: CGFloat {
        Layout.height
    }

    private func updateBottomNavigationLayout() {
        bottomNavigationHeightConstraint?.constant = bottomNavigationHeight
        bottomNavigationView.refreshDisplayScale()
    }

    private func stack(for item: PostListBottomNavigationItem) -> UINavigationController {
        if let existing = stacks[item] {
            return existing
        }
        let stack = makeStack(for: item)
        stacks[item] = stack
        return stack
    }

    private func show(_ stack: UINavigationController) {
        if stack.parent == nil {
            addChild(stack)
            stack.view.translatesAutoresizingMaskIntoConstraints = false
            stack.view.isHidden = true
            containerView.addSubview(stack.view)
            NSLayoutConstraint.activate([
                stack.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                stack.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                stack.view.topAnchor.constraint(equalTo: containerView.topAnchor),
                stack.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            stack.didMove(toParent: self)
        }

        guard visibleStack !== stack else {
            stack.view.isHidden = false
            stack.view.alpha = 1
            stack.view.isUserInteractionEnabled = true
            containerView.bringSubviewToFront(stack.view)
            return
        }

        // Keep the rendered tab visible until the target hierarchy has completed layout.
        // This avoids exposing a transient system-background frame while a tab creates its content.
        let previousStack = visibleStack
        // Update immediately so a rapid second tab tap transitions from this pending target,
        // rather than reviving the page that is currently fading out.
        visibleStack = stack
        stack.view.isHidden = false
        stack.view.alpha = 0
        stack.view.isUserInteractionEnabled = true
        stack.view.setNeedsLayout()
        stack.view.layoutIfNeeded()
        containerView.bringSubviewToFront(stack.view)

        guard let previousStack else {
            stack.view.alpha = 1
            return
        }

        previousStack.view.isHidden = false
        previousStack.view.isUserInteractionEnabled = false
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            stack.view.alpha = 1
            previousStack.view.alpha = 0
        } completion: { [weak self, weak previousStack] _ in
            previousStack?.view.alpha = 1
            previousStack?.view.isHidden = true
            self?.visibleStack = stack
        }
    }

    private func recoverVisibleContent(in stack: UINavigationController) {
        stack.view.setNeedsLayout()
        stack.view.layoutIfNeeded()
        (stack.viewControllers.first as? PostListViewController)?.recoverVisiblePageIfNeeded()
    }

    private func resetToTop(of stack: UINavigationController) {
        stack.popToRootViewController(animated: false)
        guard let root = stack.viewControllers.first else { return }
        let scrollViews = findScrollViews(in: root.view)
        guard let scrollView = scrollViews.max(by: { $0.bounds.height < $1.bounds.height }) else { return }
        let topOffset = CGPoint(x: -scrollView.adjustedContentInset.left, y: -scrollView.adjustedContentInset.top)
        scrollView.setContentOffset(topOffset, animated: false)
    }

    private func refreshHistoryListIfVisible(in stack: UINavigationController) {
        // 正在阅读历史详情时保留该页面，回到历史列表后再刷新记录。
        guard let history = stack.topViewController as? RecentVisitedPostsViewController else {
            return
        }
        history.refreshFromTabSelection()
    }

    /// 切回板块/tab 时，对已展示的列表重播流式输出（正在加载/刷新时由数据到达后的 setItems 负责）。
    private func replayStreamAppearanceIfNeeded(for item: PostListBottomNavigationItem) {
        guard let root = stacks[item]?.viewControllers.first else { return }
        switch item {
        case .home:
            (root as? PostListViewController)?.replayStreamAppearanceIfNeeded()
        case .history:
            (root as? RecentVisitedPostsViewController)?.replayStreamAppearance()
        case .search:
            (root as? SearchViewController)?.replayStreamAppearance()
        case .messages, .profile:
            break
        }
    }

    /// 双击底栏按钮：只刷新当前页面的内容。
    private func doubleTapRefresh(_ item: PostListBottomNavigationItem) {
        let stack = stack(for: item)
        guard let root = stack.viewControllers.first else { return }
        switch item {
        case .home:
            (root as? PostListViewController)?.refreshVisibleFirstPageIfNeeded()
        case .history:
            (root as? RecentVisitedPostsViewController)?.refreshFromTabSelection()
        case .search:
            (root as? SearchViewController)?.refreshFromDoubleTap()
        case .messages:
            (root as? NotificationViewController)?.refreshFromDoubleTap()
        case .profile:
            (root as? ProfileTabViewController)?.refreshFromDoubleTap()
        }
    }

    private func refreshHomeListIfVisible(in stack: UINavigationController) {
        // 仅当首页位于第一级帖子列表时静默刷新；帖子详情页在导航栈顶时不刷新。
        guard let postList = stack.topViewController as? PostListViewController else {
            return
        }
        postList.refreshVisibleFirstPageIfNeeded()
    }

    private func findScrollViews(in view: UIView) -> [UIScrollView] {
        var result: [UIScrollView] = []
        if let scrollView = view as? UIScrollView,
           scrollView.isScrollEnabled,
           scrollView.bounds.height > 0 {
            result.append(scrollView)
        }
        for subview in view.subviews where subview.isHidden == false {
            result.append(contentsOf: findScrollViews(in: subview))
        }
        return result
    }

    private func makeStack(for item: PostListBottomNavigationItem) -> UINavigationController {
        let root: UIViewController
        switch item {
        case .home:
            let home = PostListRouter.createModule()
            if let postList = home as? PostListViewController {
                postList.showsBottomNavigation = false
                postList.onUnreadBadgeChange = { [weak self] visible in
                    self?.unreadBadgeVisible = visible
                    self?.bottomNavigationView.setUnreadMessagesVisible(visible)
                }
            }
            root = home
        case .history:
            let history = RecentVisitedPostsViewController(visitedStore: VisitedPostStore.shared)
            history.onSelectRecord = { [weak history] record in
                let post = Self.postSummary(from: record)
                let detail = PostDetailRouter.createModule(post: post, page: 1, initialAnchorID: nil)
                history?.navigationController?.pushViewController(detail, animated: true)
            }
            root = history
        case .search:
            root = SearchViewController()
        case .messages:
            root = NotificationViewController()
        case .profile:
            root = ProfileTabViewController()
        }
        root.navigationItem.hidesBackButton = true
        return UINavigationController(rootViewController: root)
    }
    private static func postSummary(from record: VisitedPostRecord) -> PostSummary {
        PostSummary(
            id: record.postID,
            title: record.title,
            url: record.url,
            authorName: "",
            nodeName: nil,
            replyCount: record.replyCount,
            viewCount: record.viewCount,
            lastActivityText: nil,
            avatarURL: record.avatarURL
        )
    }
}
