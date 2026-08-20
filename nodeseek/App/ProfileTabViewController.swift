//
//  ProfileTabViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class ProfileTabViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case content
        case utility
    }

    private enum ContentRow: Int, CaseIterable {
        case discussions
        case comments
        case collections

        var title: String {
            switch self {
            case .discussions: return "主题帖"
            case .comments: return "评论"
            case .collections: return "收藏"
            }
        }

        var imageName: String {
            switch self {
            case .discussions: return "doc.text"
            case .comments: return "text.bubble"
            case .collections: return "bookmark"
            }
        }
    }

    private let requestedUserID: Int?
    private let userInfoClient: NodeSeekUserInfoLoading
    private let relationshipClient: NodeSeekUserRelationshipManaging
    private let currentAccountStore: CurrentAccountStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = ProfileHeaderView()
    private let refreshControl = UIRefreshControl()
    private var activeUserID: Int?
    private var currentUserID: Int?
    private var account: AccountResponse?
    private var userInfo: NodeSeekUserInfo?
    private var loadTask: Task<Void, Never>?
    private var isChangingFollowState = false

    init(
        userID: Int? = nil,
        userInfoClient: NodeSeekUserInfoLoading? = nil,
        relationshipClient: NodeSeekUserRelationshipManaging? = nil,
        currentAccountStore: CurrentAccountStore = .shared
    ) {
        requestedUserID = userID
        self.userInfoClient = userInfoClient ?? NodeSeekUserInfoClient()
        self.relationshipClient = relationshipClient ?? NodeSeekUserRelationshipClient()
        self.currentAccountStore = currentAccountStore
        super.init(nibName: nil, bundle: nil)
        title = userID == nil ? "我的" : "用户资料"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureTableView()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "刷新资料"
        loadProfile()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let desiredWidth = tableView.bounds.width
        guard desiredWidth > 0 else { return }
        let desiredHeight = headerView.preferredHeight
        guard abs(headerView.bounds.width - desiredWidth) > 0.5 ||
              abs(headerView.bounds.height - desiredHeight) > 0.5 else { return }
        headerView.frame = CGRect(x: 0, y: 0, width: desiredWidth, height: desiredHeight)
        tableView.tableHeaderView = headerView
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 52
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProfileCell")
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableView.refreshControl = refreshControl
        headerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: headerView.preferredHeight)
        tableView.tableHeaderView = headerView
        headerView.onPrivateMessageTapped = { [weak self] in
            self?.openPrivateMessage()
        }
        headerView.onFollowTapped = { [weak self] in
            self?.followUser()
        }
        headerView.onTransferTapped = { [weak self] in
            self?.openStardustTransfer()
        }
        headerView.onHeightNeedsUpdate = { [weak self, weak headerView] in
            guard let self, let headerView else { return }
            let desiredHeight = headerView.preferredHeight
            guard abs(headerView.bounds.height - desiredHeight) > 0.5 else { return }
            headerView.frame = CGRect(x: 0, y: 0, width: self.tableView.bounds.width, height: desiredHeight)
            self.tableView.tableHeaderView = headerView
        }

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadProfile() {
        loadTask?.cancel()
        let hasVisibleProfile = userInfo != nil
        if hasVisibleProfile == false {
            headerView.setLoading()
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            let account = await currentAccountStore.snapshot()?.account
            guard Task.isCancelled == false else { return }
            self.account = account
            currentUserID = account?.nodeSeekUID
            guard let userID = requestedUserID ?? currentUserID else {
                activeUserID = nil
                userInfo = nil
                headerView.setSignedOut()
                refreshControl.endRefreshing()
                tableView.reloadData()
                return
            }

            activeUserID = userID
            for attempt in 0...1 {
                do {
                    let info = try await userInfoClient.loadUserInfo(userID: userID)
                    guard Task.isCancelled == false else { return }
                    userInfo = info
                    headerView.configure(
                        userInfo: info,
                        avatarURL: avatarURL(for: userID),
                        isCurrentUser: userID == currentUserID
                    )
                    refreshControl.endRefreshing()
                    tableView.reloadData()
                    return
                } catch {
                    guard Task.isCancelled == false else { return }
                    if attempt == 0, Self.isTemporaryServerError(error) {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        guard Task.isCancelled == false else { return }
                        continue
                    }

                    // A transient failure must not replace an already usable profile with a blank error state.
                    if hasVisibleProfile == false {
                        userInfo = nil
                        headerView.setError(error.localizedDescription)
                    } else {
                        AppLog.warning(.account, "个人资料刷新失败，保留已展示内容: \(error.localizedDescription)")
                    }
                }
            }
            refreshControl.endRefreshing()
            tableView.reloadData()
        }
    }

    private static func isTemporaryServerError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("503") || message.contains("service unavailable")
    }

    private func avatarURL(for userID: Int) -> URL {
        if userID == currentUserID, let avatarURL = account?.avatarURL {
            return avatarURL
        }
        return NodeSeekNotificationURLBuilder.avatarURL(memberID: userID)
    }

    @objc private func refreshTapped() {
        loadProfile()
    }

    /// 双击我的 tab：重新加载当前资料页。
    func refreshFromDoubleTap() {
        loadProfile()
    }

    @objc private func refreshTriggered() {
        loadProfile()
    }

    private func openContent(_ row: ContentRow) {
        guard let userID = activeUserID else { return }
        let viewController: UIViewController
        switch row {
        case .discussions:
            let discussions = UserDiscussionsViewController(
                userID: userID,
                authorName: userInfo?.username,
                avatarURL: avatarURL(for: userID)
            )
            discussions.onSelectPost = { [weak self] post, page, anchorID in
                self?.openPost(post, page: page, anchorID: anchorID)
            }
            viewController = discussions
        case .comments:
            let comments = UserCommentsViewController(userID: userID)
            comments.onSelectPost = { [weak self] post, page, anchorID in
                self?.openPost(post, page: page, anchorID: anchorID)
            }
            viewController = comments
        case .collections:
            let collections = UserCollectionsViewController(
                userID: userID,
                authorName: userInfo?.username,
                avatarURL: avatarURL(for: userID)
            )
            collections.onSelectPost = { [weak self] post, page, anchorID in
                self?.openPost(post, page: page, anchorID: anchorID)
            }
            viewController = collections
        }
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func openPost(_ post: PostSummary, page: Int, anchorID: String?) {
        navigationController?.pushViewController(
            PostDetailRouter.createModule(post: post, page: page, initialAnchorID: anchorID),
            animated: true
        )
    }

    private func openPrivateMessage() {
        guard let userID = activeUserID,
              userID != currentUserID else {
            return
        }
        let participantName = userInfo?.username ?? "用户 \(userID)"
        navigationController?.pushViewController(
            PrivateMessageViewController(participantID: userID, participantName: participantName),
            animated: true
        )
    }

    private func followUser() {
        guard let userID = activeUserID,
              userID != currentUserID,
              isChangingFollowState == false else {
            return
        }
        guard currentUserID != nil else {
            presentMessage(title: "请先登录", message: "登录后才能关注用户。")
            return
        }
        isChangingFollowState = true
        headerView.setFollowLoading(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await relationshipClient.setFollowing(userID: userID, following: true)
                isChangingFollowState = false
                headerView.setFollowing(true)
                headerView.setFollowLoading(false)
            } catch {
                isChangingFollowState = false
                headerView.setFollowLoading(false)
                presentMessage(title: "关注失败", message: error.localizedDescription)
            }
        }
    }

    private func openStardustTransfer() {
        guard let userID = activeUserID,
              userID != currentUserID else {
            return
        }
        guard currentUserID != nil else {
            presentMessage(title: "请先登录", message: "登录后才能进行星辰转账。")
            return
        }
        let recipientName = userInfo?.username ?? "用户 \(userID)"
        navigationController?.pushViewController(
            StardustTransferViewController(
                recipientID: userID,
                recipientName: recipientName,
                client: relationshipClient
            ),
            animated: true
        )
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

extension ProfileTabViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .content:
            return ContentRow.allCases.count
        case .utility:
            return requestedUserID == nil ? 1 : 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .content:
            return "内容"
        case .utility:
            return requestedUserID == nil ? "应用" : nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileCell", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        let section = Section(rawValue: indexPath.section)
        switch section {
        case .content:
            let row = ContentRow(rawValue: indexPath.row)!
            configuration.text = row.title
            configuration.image = UIImage(systemName: row.imageName)
            configuration.imageProperties.tintColor = .systemOrange
            cell.accessoryType = .disclosureIndicator
            cell.isUserInteractionEnabled = activeUserID != nil
            configuration.textProperties.color = activeUserID == nil ? .secondaryLabel : .label
        case .utility:
            configuration.text = "设置"
            configuration.image = UIImage(systemName: "gearshape")
            configuration.imageProperties.tintColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            cell.isUserInteractionEnabled = true
        case .none:
            break
        }
        cell.contentConfiguration = configuration
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .content:
            guard let row = ContentRow(rawValue: indexPath.row), activeUserID != nil else { return }
            openContent(row)
        case .utility:
            navigationController?.pushViewController(SettingsViewController(), animated: true)
        }
    }
}

private final class ProfileHeaderView: UIView {
    static let preferredHeight: CGFloat = 252

    /// 依据操作按钮是否可见动态计算头部高度：本人页面隐藏按钮，减少主题帖上方的空白。
    var preferredHeight: CGFloat {
        actionStack.isHidden ? 196 : 252
    }

    var onHeightNeedsUpdate: (() -> Void)?

    var onPrivateMessageTapped: (() -> Void)?
    var onFollowTapped: (() -> Void)?
    var onTransferTapped: (() -> Void)?

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let levelLabel = UILabel()
    private let statusLabel = UILabel()
    private let metricContainer = UIView()
    private let metricStack = UIStackView()
    private let actionStack = UIStackView()
    private let transferButton = UIButton(type: .system)
    private let followButton = UIButton(type: .system)
    private let privateMessageButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGroupedBackground
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLoading() {
        avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarImageView.tintColor = .tertiaryLabel
        nameLabel.text = "正在加载"
        levelLabel.text = nil
        statusLabel.text = ""
        setActionsVisible(false)
        setMetrics(Self.placeholderMetrics)
    }

    func setSignedOut() {
        avatarImageView.image = UIImage(systemName: "person.crop.circle.badge.questionmark")
        avatarImageView.tintColor = .secondaryLabel
        nameLabel.text = "未登录"
        levelLabel.text = nil
        statusLabel.text = "登录后可查看个人资料"
        setActionsVisible(false)
        setMetrics(Self.placeholderMetrics)
    }

    func setError(_ message: String) {
        avatarImageView.image = UIImage(systemName: "exclamationmark.circle")
        avatarImageView.tintColor = .systemOrange
        nameLabel.text = "资料加载失败"
        levelLabel.text = nil
        statusLabel.text = message
        setActionsVisible(false)
        setMetrics(Self.placeholderMetrics)
    }

    func configure(userInfo: NodeSeekUserInfo, avatarURL: URL, isCurrentUser: Bool) {
        avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarImageView.tintColor = .tertiaryLabel
        ImageLoad.url(avatarURL)
            .toAvatar(requestID: "profile-\(userInfo.userID)")
            .into(avatarImageView)
        nameLabel.text = userInfo.username ?? (isCurrentUser ? "我的账号" : "用户 \(userInfo.userID)")
        levelLabel.text = "等级 Lv \(userInfo.level)"
        let bio = userInfo.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        statusLabel.text = bio.isEmpty ? "加入 NodeSeek \(userInfo.joinDays) 天" : bio
        setActionsVisible(!isCurrentUser)
        setFollowing(false)
        setMetrics([
            ("等级", "Lv \(userInfo.level)", UIImage(systemName: "diamond")),
            ("主题帖", "\(userInfo.nPost)", UIImage(systemName: "square.and.pencil")),
            ("鸡腿", "\(userInfo.coin)", ReactionIconRenderer.chickenLeg(pointSize: 18)),
            ("评论数", "\(userInfo.nComment)", UIImage(systemName: "text.bubble")),
            ("星辰", "\(userInfo.stardust)", UIImage(systemName: "wallet.pass")),
            ("粉丝", "\(userInfo.fans)", UIImage(systemName: "dot.radiowaves.left.and.right"))
        ])
    }

    func setFollowLoading(_ isLoading: Bool) {
        followButton.configuration?.showsActivityIndicator = isLoading
        followButton.isEnabled = !isLoading
    }

    func setFollowing(_ isFollowing: Bool) {
        var configuration = followButton.configuration ?? UIButton.Configuration.filled()
        configuration.title = isFollowing ? "已关注" : "关注"
        configuration.image = UIImage(systemName: isFollowing ? "checkmark" : "person.badge.plus")
        configuration.imagePadding = 5
        configuration.baseBackgroundColor = isFollowing ? .systemGray : .systemBlue
        configuration.baseForegroundColor = .white
        followButton.configuration = configuration
        followButton.accessibilityLabel = isFollowing ? "已关注" : "关注用户"
    }

    private func setupUI() {
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 36

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .preferredFont(forTextStyle: .title2)
        nameLabel.textColor = .label
        nameLabel.adjustsFontForContentSizeCategory = true

        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        levelLabel.font = .preferredFont(forTextStyle: .subheadline)
        levelLabel.textColor = .systemOrange
        levelLabel.adjustsFontForContentSizeCategory = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 2

        metricContainer.translatesAutoresizingMaskIntoConstraints = false
        metricContainer.backgroundColor = .secondarySystemBackground
        metricContainer.layer.cornerRadius = 10
        metricContainer.layer.cornerCurve = .continuous

        metricStack.translatesAutoresizingMaskIntoConstraints = false
        metricStack.axis = .vertical
        metricStack.distribution = .fillEqually
        metricStack.spacing = 3
        metricContainer.addSubview(metricStack)

        configureActionButton(transferButton, title: "转账", imageName: "arrow.left.arrow.right", color: .systemGreen)
        configureActionButton(privateMessageButton, title: "私信", imageName: "paperplane.fill", color: .systemGreen)
        setFollowing(false)
        transferButton.addTarget(self, action: #selector(transferTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)
        privateMessageButton.addTarget(self, action: #selector(privateMessageTapped), for: .touchUpInside)

        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .horizontal
        actionStack.alignment = .fill
        actionStack.distribution = .fillEqually
        actionStack.spacing = 12
        actionStack.addArrangedSubview(transferButton)
        actionStack.addArrangedSubview(followButton)
        actionStack.addArrangedSubview(privateMessageButton)

        addSubview(avatarImageView)
        addSubview(nameLabel)
        addSubview(levelLabel)
        addSubview(statusLabel)
        addSubview(metricContainer)
        addSubview(actionStack)
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            avatarImageView.widthAnchor.constraint(equalToConstant: 72),
            avatarImageView.heightAnchor.constraint(equalToConstant: 72),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            levelLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            levelLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            levelLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: levelLabel.bottomAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            metricContainer.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            metricContainer.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            metricContainer.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 12),
            metricContainer.heightAnchor.constraint(equalToConstant: 80),

            metricStack.leadingAnchor.constraint(equalTo: metricContainer.layoutMarginsGuide.leadingAnchor),
            metricStack.trailingAnchor.constraint(equalTo: metricContainer.layoutMarginsGuide.trailingAnchor),
            metricStack.topAnchor.constraint(equalTo: metricContainer.layoutMarginsGuide.topAnchor),
            metricStack.bottomAnchor.constraint(equalTo: metricContainer.layoutMarginsGuide.bottomAnchor),

            actionStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            actionStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            actionStack.topAnchor.constraint(equalTo: metricContainer.bottomAnchor, constant: 10),
            actionStack.heightAnchor.constraint(equalToConstant: 44)
        ])
        setLoading()
    }

    private func configureActionButton(_ button: UIButton, title: String, imageName: String, color: UIColor) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: imageName)
        configuration.imagePadding = 5
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    private func setActionsVisible(_ isVisible: Bool) {
        actionStack.isHidden = !isVisible
        actionStack.isUserInteractionEnabled = isVisible
        onHeightNeedsUpdate?()
    }

    private func setMetrics(_ metrics: [(String, String, UIImage?)]) {
        metricStack.arrangedSubviews.forEach {
            metricStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for row in stride(from: 0, to: metrics.count, by: 2) {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually
            rowStack.spacing = 12
            rowStack.addArrangedSubview(ProfileMetricView(title: metrics[row].0, value: metrics[row].1, image: metrics[row].2))
            if row + 1 < metrics.count {
                rowStack.addArrangedSubview(ProfileMetricView(title: metrics[row + 1].0, value: metrics[row + 1].1, image: metrics[row + 1].2))
            } else {
                rowStack.addArrangedSubview(UIView())
            }
            metricStack.addArrangedSubview(rowStack)
        }
    }

    @objc private func transferTapped() {
        onTransferTapped?()
    }

    @objc private func followTapped() {
        onFollowTapped?()
    }

    @objc private func privateMessageTapped() {
        onPrivateMessageTapped?()
    }

    private static let placeholderMetrics: [(String, String, UIImage?)] = [
        ("等级", "-", UIImage(systemName: "diamond")),
        ("主题帖", "-", UIImage(systemName: "square.and.pencil")),
        ("鸡腿", "-", ReactionIconRenderer.chickenLeg(pointSize: 18)),
        ("评论数", "-", UIImage(systemName: "text.bubble")),
        ("星辰", "-", UIImage(systemName: "wallet.pass")),
        ("粉丝", "-", UIImage(systemName: "dot.radiowaves.left.and.right"))
    ]
}

private final class ProfileMetricView: UIView {
    private let imageView = UIImageView()
    private let textLabel = UILabel()

    init(title: String, value: String, image: UIImage?) {
        super.init(frame: .zero)
        imageView.image = image
        textLabel.text = "\(title) \(value)"
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = .preferredFont(forTextStyle: .body)
        textLabel.textColor = .label
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.minimumScaleFactor = 0.72

        addSubview(imageView)
        addSubview(textLabel)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
            textLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }
}
