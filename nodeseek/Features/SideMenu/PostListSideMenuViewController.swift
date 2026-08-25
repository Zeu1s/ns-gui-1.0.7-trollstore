//
//  PostListSideMenuViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/29.
//

import UIKit

@MainActor
final class PostListSideMenuViewController: UIViewController {
    private var sideMenuLeadingConstraint: NSLayoutConstraint?
    private var isSideMenuVisible = false
    var onLoginTapped: (() -> Void)?
    var onAccountProfileTapped: ((URL) -> Void)?
    var onNewDiscussionTapped: (() -> Void)?
    var onCheckInTapped: (() -> Void)?
    var onLotteryTapped: (() -> Void)?
    var onRecentVisitedTapped: (() -> Void)?
    var onUserDiscussionsTapped: (() -> Void)?
    var onUserCommentsTapped: (() -> Void)?
    var onUserCollectionsTapped: (() -> Void)?
    var onSearchTapped: (() -> Void)?
    var onSettingsTapped: (() -> Void)?
    private let accountController: PostListSideMenuAccountController
    private let avatarLoader = AvatarImageLoader.shared
    private var extensionEntriesHeightConstraint: NSLayoutConstraint?
    private var menuStackTopConstraint: NSLayoutConstraint?

    private static let defaultAvatarImage: UIImage? = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        return UIImage(systemName: "person.crop.circle.fill", withConfiguration: configuration)
    }()

    private let backdropView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        view.alpha = 0
        view.isHidden = true
        view.accessibilityIdentifier = "post-list-side-menu-backdrop"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let sideMenuView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.14
        view.layer.shadowRadius = 18
        view.layer.shadowOffset = CGSize(width: 4, height: 0)
        view.accessibilityIdentifier = "post-list-side-menu"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = PostListSideMenuViewController.defaultAvatarImage
        imageView.tintColor = .tertiaryLabel
        imageView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = SideMenuLayout.avatarSize / 2
        imageView.isUserInteractionEnabled = true
        imageView.accessibilityIdentifier = "post-list-side-menu-avatar"
        imageView.accessibilityLabel = "用户头像"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.text = "未登录"
        label.font = .systemFont(ofSize: 19, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityIdentifier = "post-list-side-menu-name-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statsLabel: UILabel = {
        let label = UILabel()
        label.text = "登录后同步账号信息"
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityIdentifier = "post-list-side-menu-stats-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let accountHeaderButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.accessibilityIdentifier = "post-list-side-menu-account-header-button"
        button.accessibilityLabel = "登录账号"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let extensionEntryStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.isHidden = true
        stackView.accessibilityIdentifier = "post-list-side-menu-extension-entry-stack"
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let postsEntryButton: UIButton = {
        let button = PostListSideMenuViewController.makeExtensionEntryButton(label: "帖子", systemImageName: "list.bullet")
        button.accessibilityIdentifier = "post-list-side-menu-extension-posts-button"
        return button
    }()

    private let commentsEntryButton: UIButton = {
        let button = PostListSideMenuViewController.makeExtensionEntryButton(label: "评论", systemImageName: "bubble.left")
        button.accessibilityIdentifier = "post-list-side-menu-extension-comments-button"
        return button
    }()

    private let favoritesEntryButton: UIButton = {
        let button = PostListSideMenuViewController.makeExtensionEntryButton(label: "收藏", systemImageName: "bookmark")
        button.accessibilityIdentifier = "post-list-side-menu-extension-favorites-button"
        return button
    }()

    private let settingsButton: UIButton = {
        let button = PostListSideMenuViewController.makeMenuButton(title: "设置", systemImageName: "gearshape")
        button.accessibilityIdentifier = "post-list-side-menu-settings-button"
        return button
    }()

    private let recentVisitedButton: UIButton = {
        let button = PostListSideMenuViewController.makeMenuButton(title: "最近浏览", systemImageName: "clock.arrow.circlepath")
        button.accessibilityIdentifier = "post-list-side-menu-recent-visited-button"
        return button
    }()

    private let searchButton: UIButton = {
        let button = PostListSideMenuViewController.makeMenuButton(title: "搜一搜", systemImageName: "magnifyingglass")
        button.accessibilityIdentifier = "post-list-side-menu-search-button"
        return button
    }()

    private let newDiscussionButton: UIButton = {
        let button = PostListSideMenuViewController.makeMenuButton(title: "发帖", systemImageName: "square.and.pencil")
        button.accessibilityIdentifier = "post-list-side-menu-new-discussion-button"
        return button
    }()

    private let checkInButton: UIButton = {
        let button = PostListSideMenuViewController.makeMenuButton(title: "签到", systemImageName: "checkmark.seal")
        button.accessibilityIdentifier = "post-list-side-menu-check-in-button"
        return button
    }()

    private let lotteryButton: UIButton = {
        let button = PostListSideMenuViewController.makeMenuButton(title: "抽奖", systemImageName: "gift")
        button.accessibilityIdentifier = "post-list-side-menu-lottery-button"
        return button
    }()

    private let menuStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 2
        stackView.accessibilityIdentifier = "post-list-side-menu-actions"
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    init(
        currentAccountStore: CurrentAccountStore = .shared,
        accountRefresher: (any CurrentAccountRefreshing)? = nil,
        refreshMaxAge: TimeInterval = 60
    ) {
        self.accountController = PostListSideMenuAccountController(
            currentAccountStore: currentAccountStore,
            accountRefresher: accountRefresher,
            refreshMaxAge: refreshMaxAge
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureAccountController()
        accountController.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        avatarImageView.layer.cornerRadius = avatarImageView.bounds.width / 2
    }

    private static func makeMenuButton(title: String, systemImageName: String) -> UIButton {
        let button = UIButton(type: .system)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemImageName, withConfiguration: symbolConfiguration)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 16, weight: .medium)
            return outgoing
        }
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private static func makeExtensionEntryButton(label: String, systemImageName: String) -> UIButton {
        let button = UIButton(type: .system)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemImageName, withConfiguration: symbolConfiguration)
        configuration.imagePadding = 2
        configuration.imagePlacement = .leading
        configuration.title = label
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: .medium)
            return outgoing
        }
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)
        button.configuration = configuration
        button.backgroundColor = .clear
        button.accessibilityLabel = label
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func show(animated: Bool) {
        accountController.refreshIfNeeded()
        setVisible(true, animated: animated)
    }

    func hide(animated: Bool) {
        setVisible(false, animated: animated)
    }

    func openAccountProfileOrLogin() {
        accountController.refreshIfNeeded()
        Task { [weak self] in
            guard let self else { return }
            if let account = await accountControllerStoredAccount(),
               account.isLoggedIn,
               let profileURL = account.profileURL {
                renderAccount(account)
                onAccountProfileTapped?(profileURL)
                return
            }

            guard accountController.isLoggedIn, let profileURL = accountController.profileURL else {
                onLoginTapped?()
                return
            }
            onAccountProfileTapped?(profileURL)
        }
    }

    private func accountControllerStoredAccount() async -> AccountResponse? {
        await accountController.currentAccountSnapshot()
    }

    private func renderAccount(_ account: AccountResponse) {
        nameLabel.text = account.isLoggedIn ? account.displayName : "未登录"
        statsLabel.text = account.isLoggedIn
            ? account.stats.prefix(3).joined(separator: " · ")
            : "登录后同步账号信息"
        accountHeaderButton.accessibilityLabel = account.isLoggedIn ? "账号信息" : "登录账号"
        accountHeaderButton.isEnabled = !account.isLoggedIn || account.profileURL != nil
        setExtensionEntriesVisible(account.isLoggedIn)

        if account.isLoggedIn {
            ImageLoad.url(account.avatarURL)
                .toAvatar(requestID: account.profileURL?.lastPathComponent ?? account.displayName)
                .into(avatarImageView)
        } else {
            avatarLoader.cancel(on: avatarImageView)
            avatarImageView.image = Self.defaultAvatarImage
            avatarImageView.tintColor = .tertiaryLabel
        }
    }

    private func configureAccountController() {
        accountController.canRefresh = { [weak self] in
            self?.view.window != nil
        }
        accountController.isSideMenuVisible = { [weak self] in
            self?.isSideMenuVisible == true
        }
        accountController.onAccountChanged = { [weak self] account in
            self?.renderAccount(account)
        }
    }

    private func setupUI() {
        view.backgroundColor = .clear
        view.isHidden = true
        backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped)))
        accountHeaderButton.addTarget(self, action: #selector(accountHeaderTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        newDiscussionButton.addTarget(self, action: #selector(newDiscussionButtonTapped), for: .touchUpInside)
        checkInButton.addTarget(self, action: #selector(checkInButtonTapped), for: .touchUpInside)
        lotteryButton.addTarget(self, action: #selector(lotteryButtonTapped), for: .touchUpInside)
        recentVisitedButton.addTarget(self, action: #selector(recentVisitedButtonTapped), for: .touchUpInside)
        searchButton.addTarget(self, action: #selector(searchButtonTapped), for: .touchUpInside)
        postsEntryButton.addTarget(self, action: #selector(postsEntryButtonTapped), for: .touchUpInside)
        commentsEntryButton.addTarget(self, action: #selector(commentsEntryButtonTapped), for: .touchUpInside)
        favoritesEntryButton.addTarget(self, action: #selector(favoritesEntryButtonTapped), for: .touchUpInside)

        view.addSubview(backdropView)
        view.addSubview(sideMenuView)
        sideMenuView.addSubview(avatarImageView)
        sideMenuView.addSubview(nameLabel)
        sideMenuView.addSubview(statsLabel)
        sideMenuView.addSubview(accountHeaderButton)
        sideMenuView.addSubview(extensionEntryStackView)
        extensionEntryStackView.addArrangedSubview(postsEntryButton)
        extensionEntryStackView.addArrangedSubview(commentsEntryButton)
        extensionEntryStackView.addArrangedSubview(favoritesEntryButton)
        sideMenuView.addSubview(menuStackView)
        menuStackView.addArrangedSubview(newDiscussionButton)
        menuStackView.addArrangedSubview(checkInButton)
        menuStackView.addArrangedSubview(lotteryButton)
        menuStackView.addArrangedSubview(searchButton)
        menuStackView.addArrangedSubview(recentVisitedButton)
        menuStackView.addArrangedSubview(settingsButton)

        let sideMenuLeadingConstraint = sideMenuView.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: -SideMenuLayout.width
        )
        self.sideMenuLeadingConstraint = sideMenuLeadingConstraint

        let extensionEntriesHeightConstraint = extensionEntryStackView.heightAnchor.constraint(equalToConstant: 0)
        let menuStackTopConstraint = menuStackView.topAnchor.constraint(
            equalTo: extensionEntryStackView.bottomAnchor,
            constant: 12
        )
        self.extensionEntriesHeightConstraint = extensionEntriesHeightConstraint
        self.menuStackTopConstraint = menuStackTopConstraint

        NSLayoutConstraint.activate([
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sideMenuLeadingConstraint,
            sideMenuView.topAnchor.constraint(equalTo: view.topAnchor),
            sideMenuView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sideMenuView.widthAnchor.constraint(equalToConstant: SideMenuLayout.width),

            avatarImageView.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            avatarImageView.topAnchor.constraint(equalTo: sideMenuView.safeAreaLayoutGuide.topAnchor, constant: 24),
            avatarImageView.widthAnchor.constraint(equalToConstant: SideMenuLayout.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: SideMenuLayout.avatarSize),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: 8),

            // Put account stats on their own full-width line so compact values such as "星辰 6"
            // never wrap after the avatar column.
            statsLabel.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            statsLabel.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            statsLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 10),

            accountHeaderButton.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor),
            accountHeaderButton.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            accountHeaderButton.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -8),
            accountHeaderButton.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 8),

            extensionEntryStackView.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            extensionEntryStackView.trailingAnchor.constraint(lessThanOrEqualTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            extensionEntryStackView.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 7),
            extensionEntriesHeightConstraint,

            postsEntryButton.heightAnchor.constraint(equalToConstant: 24),
            commentsEntryButton.heightAnchor.constraint(equalToConstant: 24),
            favoritesEntryButton.heightAnchor.constraint(equalToConstant: 24),

            menuStackView.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            menuStackView.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            menuStackTopConstraint,
            menuStackView.bottomAnchor.constraint(lessThanOrEqualTo: sideMenuView.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            newDiscussionButton.heightAnchor.constraint(equalToConstant: 48),
            checkInButton.heightAnchor.constraint(equalToConstant: 48),
            lotteryButton.heightAnchor.constraint(equalToConstant: 48),
            searchButton.heightAnchor.constraint(equalToConstant: 48),
            recentVisitedButton.heightAnchor.constraint(equalToConstant: 48),
            settingsButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func setExtensionEntriesVisible(_ isVisible: Bool) {
        extensionEntryStackView.isHidden = !isVisible
        postsEntryButton.isHidden = !isVisible
        commentsEntryButton.isHidden = !isVisible
        favoritesEntryButton.isHidden = !isVisible
        extensionEntriesHeightConstraint?.constant = isVisible ? 24 : 0
        menuStackTopConstraint?.constant = isVisible ? 12 : 14
        view.setNeedsLayout()
    }

    @objc private func backdropTapped() {
        hide(animated: true)
    }

    @objc private func accountHeaderTapped() {
        if accountController.isLoggedIn {
            guard let profileURL = accountController.profileURL else { return }
            hide(animated: true)
            onAccountProfileTapped?(profileURL)
            return
        }

        hide(animated: true)
        onLoginTapped?()
    }

    @objc private func settingsButtonTapped() {
        hide(animated: true)
        onSettingsTapped?()
    }

    @objc private func newDiscussionButtonTapped() {
        AppLog.info(.postList, "侧边栏发帖按钮点击: isLoggedIn=\(accountController.isLoggedIn)")
        hide(animated: true)
        if accountController.isLoggedIn {
            AppLog.info(.postList, "侧边栏发帖按钮通过登录状态，触发新发帖")
            onNewDiscussionTapped?()
        } else {
            AppLog.warning(.postList, "侧边栏发帖按钮未登录，触发登录")
            onLoginTapped?()
        }
    }

    @objc private func checkInButtonTapped() {
        hide(animated: true)
        if accountController.isLoggedIn {
            onCheckInTapped?()
        } else {
            onLoginTapped?()
        }
    }

    @objc private func lotteryButtonTapped() {
        hide(animated: true)
        onLotteryTapped?()
    }

    @objc private func recentVisitedButtonTapped() {
        hide(animated: true)
        onRecentVisitedTapped?()
    }

    @objc private func searchButtonTapped() {
        hide(animated: true)
        onSearchTapped?()
    }

    @objc private func postsEntryButtonTapped() {
        hide(animated: true)
        onUserDiscussionsTapped?()
    }

    @objc private func commentsEntryButtonTapped() {
        hide(animated: true)
        onUserCommentsTapped?()
    }

    @objc private func favoritesEntryButtonTapped() {
        hide(animated: true)
        onUserCollectionsTapped?()
    }

    private func setVisible(_ visible: Bool, animated: Bool) {
        guard visible != isSideMenuVisible else { return }
        isSideMenuVisible = visible
        if visible {
            view.isHidden = false
            backdropView.isHidden = false
        }

        sideMenuLeadingConstraint?.constant = visible ? 0 : -SideMenuLayout.width
        let animations = { [weak self] in
            self?.backdropView.alpha = visible ? 1 : 0
            self?.view.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.view.isHidden = !self.isSideMenuVisible
            self.backdropView.isHidden = !self.isSideMenuVisible
        }

        let shouldAnimate = animated && UIView.areAnimationsEnabled
        guard shouldAnimate else {
            animations()
            completion(true)
            return
        }
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
            animations: animations,
            completion: completion
        )
    }
}

private enum SideMenuLayout {
    static let width: CGFloat = 300
    static let horizontalInset: CGFloat = 22
    static let avatarSize: CGFloat = 72
}
