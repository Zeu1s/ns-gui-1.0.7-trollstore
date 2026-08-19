//
//  MainTabContainerViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class MainTabContainerViewController: UIViewController {
    private enum Layout {
        static let horizontalInset: CGFloat = 24
        static let height: CGFloat = 74
    }

    private let containerView = UIView()
    private let bottomNavigationView = PostListBottomNavigationView()
    private var stacks: [PostListBottomNavigationItem: UINavigationController] = [:]
    private var currentItem: PostListBottomNavigationItem = .home
    private var unreadBadgeVisible = false
    private var displayScaleObserver: NSObjectProtocol?

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
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomNavigationView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Layout.horizontalInset),
            bottomNavigationView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Layout.horizontalInset),
            bottomNavigationView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomNavigationView.heightAnchor.constraint(equalToConstant: Layout.height)
        ])

        bottomNavigationView.onItemSelected = { [weak self] item in
            self?.select(item)
        }
        bottomNavigationView.setSelectedItem(.home)

        select(.home)
        observeDisplayScaleChanges()
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
            self?.bottomNavigationView.refreshDisplayScale()
        }
    }

    private func select(_ item: PostListBottomNavigationItem) {
        let stack = stack(for: item)
        currentItem = item
        show(stack)
        bottomNavigationView.setSelectedItem(item)
        bottomNavigationView.setUnreadMessagesVisible(unreadBadgeVisible)
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
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        addChild(stack)
        stack.view.frame = containerView.bounds
        stack.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(stack.view)
        stack.didMove(toParent: self)
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
            replyCount: 0,
            viewCount: 0,
            lastActivityText: nil,
            avatarURL: record.avatarURL
        )
    }
}
