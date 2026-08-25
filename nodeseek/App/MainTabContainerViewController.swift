//
//  MainTabContainerViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class MainTabContainerViewController: UIViewController {
    private enum Layout {
        static let horizontalInset: CGFloat = 0
        // 内容区固定 44pt，底部安全区由底栏统一承接，避免图标组悬在白色横幅上半部。
        static let contentHeight: CGFloat = 44
    }

    private let containerView = UIView()
    private let bottomNavigationView = PostListBottomNavigationView()
    private var stacks: [PostListBottomNavigationItem: UINavigationController] = [:]
    private var currentItem: PostListBottomNavigationItem = .home
    private weak var visibleStack: UINavigationController?
    private var unreadMessageCount = 0
    private var displayScaleObserver: NSObjectProtocol?
    private var bottomNavigationHeightConstraint: NSLayoutConstraint?
    private var hasReleasedNotificationPrefetch = false

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
            // 底栏覆盖至屏幕底部，图标、文字和选中遮罩才能在整条白色横幅中垂直居中。
            bottomNavigationView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
        releaseNotificationPrefetchAfterInitialHomeRequestIfNeeded()
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

    private func releaseNotificationPrefetchAfterInitialHomeRequestIfNeeded() {
        guard hasReleasedNotificationPrefetch == false else { return }
        hasReleasedNotificationPrefetch = true
        // 此时首页已建立当前板块页面并发出首屏请求；随后再取消息，避免冷启动抢占。
        NodeSeekNotificationPrefetcher.shared.startAfterHomePreviewRequest()
    }

    private func select(_ item: PostListBottomNavigationItem) {
        let reselectedCurrentItem = item == currentItem
        let stack = stack(for: item)
        currentItem = item
        show(stack) { [weak self, weak stack] in
            guard let self, self.currentItem == item, self.visibleStack === stack else { return }
            guard reselectedCurrentItem == false else { return }
            self.replayStreamAppearanceIfNeeded(for: item)
        }
        guard reselectedCurrentItem == false else {
            // 一级功能区内的单击只保持当前位置；双击由 doubleTapRefresh(_:) 负责刷新。
            if item == .profile {
                resetProfileToTop(in: stack)
            }
            bottomNavigationView.setSelectedItem(item)
            bottomNavigationView.setUnreadMessageCount(unreadMessageCount)
            return
        }

        switch item {
        case .home:
            // 只能复位当前帖子列表，不能触及 UIPageViewController 的横向滚动视图。
            recoverVisibleContent(in: stack)
            refreshSelectedHomeCategoryIfVisible(in: stack)
        case .history:
            refreshHistoryListIfVisible(in: stack)
        case .search:
            refreshSearchResultsIfVisible(in: stack)
        case .messages:
            refreshNotificationsIfVisible(in: stack)
        case .profile:
            recoverVisibleContent(in: stack)
        }
        bottomNavigationView.setSelectedItem(item)
        bottomNavigationView.setUnreadMessageCount(unreadMessageCount)
    }

    private var bottomNavigationHeight: CGFloat {
        Layout.contentHeight + view.safeAreaInsets.bottom
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

    private func show(_ stack: UINavigationController, completion: @escaping () -> Void) {
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
            DispatchQueue.main.async(execute: completion)
            return
        }

        let previousStack = visibleStack
        visibleStack = stack
        stack.view.isHidden = false
        stack.view.alpha = 1
        stack.view.isUserInteractionEnabled = true
        stack.view.setNeedsLayout()
        stack.view.layoutIfNeeded()
        containerView.bringSubviewToFront(stack.view)
        previousStack?.view.alpha = 1
        previousStack?.view.isHidden = true
        previousStack?.view.isUserInteractionEnabled = false
        DispatchQueue.main.async(execute: completion)
    }

    private func recoverVisibleContent(in stack: UINavigationController) {
        stack.view.setNeedsLayout()
        stack.view.layoutIfNeeded()
        (stack.viewControllers.first as? PostListViewController)?.recoverVisiblePageIfNeeded()
    }

    private func resetProfileToTop(in stack: UINavigationController) {
        guard let profile = stack.topViewController as? ProfileTabViewController else { return }
        guard let tableView = profile.view.subviews.compactMap({ $0 as? UITableView }).first else { return }
        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top),
            animated: false
        )
    }

    private func refreshHistoryListIfVisible(in stack: UINavigationController) {
        // 正在阅读历史详情时保留该页面，回到历史列表后再刷新记录。
        guard let history = stack.topViewController as? RecentVisitedPostsViewController else {
            return
        }
        history.refreshFromTabSelection()
    }

    private func refreshSearchResultsIfVisible(in stack: UINavigationController) {
        guard let search = stack.topViewController as? SearchViewController else { return }
        search.refreshFromTabSelection()
    }

    private func refreshNotificationsIfVisible(in stack: UINavigationController) {
        guard let notifications = stack.topViewController as? NotificationViewController else { return }
        notifications.refreshFromTabSelection()
    }

    /// 切回板块/tab 时，对已展示的列表重播流式输出（正在加载/刷新时由数据到达后的 setItems 负责）。
    private func replayStreamAppearanceIfNeeded(for item: PostListBottomNavigationItem) {
        guard let root = stacks[item]?.viewControllers.first else { return }
        switch item {
        case .home:
            (root as? PostListViewController)?.replayStreamAppearanceIfNeeded()
        case .history:
            // 历史列表的刷新会在数据就绪后自行播放一次流式输出；
            // 此处再重播会与 replaceItemsPreservingViewport 竞争并造成闪屏。
            break
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

    private func refreshSelectedHomeCategoryIfVisible(in stack: UINavigationController) {
        // 仅当首页位于第一级帖子列表时静默刷新；保留用户上次选择的板块，不回落到“全部”。
        guard let postList = stack.topViewController as? PostListViewController else {
            return
        }
        postList.refreshSelectedCategoryAfterTabReturn()
    }

    private func makeStack(for item: PostListBottomNavigationItem) -> UINavigationController {
        let root: UIViewController
        switch item {
        case .home:
            let home = PostListRouter.createModule()
            if let postList = home as? PostListViewController {
                postList.showsBottomNavigation = false
                postList.onUnreadBadgeCountChange = { [weak self] count in
                    self?.unreadMessageCount = count
                    self?.bottomNavigationView.setUnreadMessageCount(count)
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
