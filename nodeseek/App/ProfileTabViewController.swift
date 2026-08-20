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
            case .discussions: return "主题"
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
    private let currentAccountStore: CurrentAccountStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = ProfileHeaderView()
    private let refreshControl = UIRefreshControl()
    private var activeUserID: Int?
    private var currentUserID: Int?
    private var account: AccountResponse?
    private var userInfo: NodeSeekUserInfo?
    private var loadTask: Task<Void, Never>?

    init(
        userID: Int? = nil,
        userInfoClient: NodeSeekUserInfoLoading? = nil,
        currentAccountStore: CurrentAccountStore = .shared
    ) {
        requestedUserID = userID
        self.userInfoClient = userInfoClient ?? NodeSeekUserInfoClient()
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
        guard desiredWidth > 0, headerView.bounds.width != desiredWidth else { return }
        headerView.frame = CGRect(x: 0, y: 0, width: desiredWidth, height: 218)
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
        headerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 218)
        tableView.tableHeaderView = headerView

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
        headerView.setLoading()
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
            do {
                let info = try await userInfoClient.loadUserInfo(userID: userID)
                guard Task.isCancelled == false else { return }
                userInfo = info
                headerView.configure(
                    userInfo: info,
                    avatarURL: avatarURL(for: userID),
                    isCurrentUser: userID == currentUserID
                )
            } catch {
                guard Task.isCancelled == false else { return }
                userInfo = nil
                headerView.setError(error.localizedDescription)
            }
            refreshControl.endRefreshing()
            tableView.reloadData()
        }
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

    @objc private func refreshTriggered() {
        loadProfile()
    }

    private func openContent(_ row: ContentRow) {
        guard let userID = activeUserID else { return }
        let viewController: UIViewController
        switch row {
        case .discussions:
            let discussions = UserDiscussionsViewController(userID: userID)
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
            let collections = UserCollectionsViewController(userID: userID)
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
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let levelLabel = UILabel()
    private let statusLabel = UILabel()
    private let metricStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
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
        setMetrics([("鸡腿", "-"), ("星尘", "-"), ("主题", "-"), ("评论", "-")])
    }

    func setSignedOut() {
        avatarImageView.image = UIImage(systemName: "person.crop.circle.badge.questionmark")
        avatarImageView.tintColor = .secondaryLabel
        nameLabel.text = "未登录"
        levelLabel.text = nil
        statusLabel.text = "登录后可查看个人资料"
        setMetrics([("鸡腿", "-"), ("星尘", "-"), ("主题", "-"), ("评论", "-")])
    }

    func setError(_ message: String) {
        avatarImageView.image = UIImage(systemName: "exclamationmark.circle")
        avatarImageView.tintColor = .systemOrange
        nameLabel.text = "资料加载失败"
        levelLabel.text = nil
        statusLabel.text = message
        setMetrics([("鸡腿", "-"), ("星尘", "-"), ("主题", "-"), ("评论", "-")])
    }

    func configure(userInfo: NodeSeekUserInfo, avatarURL: URL, isCurrentUser: Bool) {
        avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarImageView.tintColor = .tertiaryLabel
        ImageLoad.url(avatarURL)
            .toAvatar(requestID: "profile-\(userInfo.userID)")
            .into(avatarImageView)
        nameLabel.text = userInfo.username ?? (isCurrentUser ? "我的账号" : "用户 \(userInfo.userID)")
        levelLabel.text = "Lv \(userInfo.level)"
        statusLabel.text = "加入 \(userInfo.joinDays) 天"
        setMetrics([
            ("鸡腿", "\(userInfo.coin)"),
            ("星尘", "\(userInfo.stardust)"),
            ("主题", "\(userInfo.nPost)"),
            ("评论", "\(userInfo.nComment)")
        ])
    }

    private func setupUI() {
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 34

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .preferredFont(forTextStyle: .title2)
        nameLabel.textColor = .label
        nameLabel.adjustsFontForContentSizeCategory = true

        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        levelLabel.font = .preferredFont(forTextStyle: .caption1)
        levelLabel.textColor = .systemOrange
        levelLabel.adjustsFontForContentSizeCategory = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 1

        metricStack.translatesAutoresizingMaskIntoConstraints = false
        metricStack.axis = .horizontal
        metricStack.alignment = .fill
        metricStack.distribution = .fillEqually

        addSubview(avatarImageView)
        addSubview(nameLabel)
        addSubview(levelLabel)
        addSubview(statusLabel)
        addSubview(metricStack)
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            avatarImageView.widthAnchor.constraint(equalToConstant: 68),
            avatarImageView.heightAnchor.constraint(equalToConstant: 68),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),

            levelLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            levelLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),

            statusLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: levelLabel.bottomAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),

            metricStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            metricStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            metricStack.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 24),
            metricStack.heightAnchor.constraint(equalToConstant: 58)
        ])
        setLoading()
    }

    private func setMetrics(_ metrics: [(String, String)]) {
        metricStack.arrangedSubviews.forEach {
            metricStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for metric in metrics {
            metricStack.addArrangedSubview(ProfileMetricView(title: metric.0, value: metric.1))
        }
    }
}

private final class ProfileMetricView: UIView {
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()

    init(title: String, value: String) {
        super.init(frame: .zero)
        valueLabel.text = value
        titleLabel.text = title
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .preferredFont(forTextStyle: .headline)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontForContentSizeCategory = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        addSubview(valueLabel)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: topAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}
