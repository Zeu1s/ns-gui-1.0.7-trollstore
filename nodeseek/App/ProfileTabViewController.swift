//
//  ProfileTabViewController.swift
//  nodeseek
//

import UIKit
import WebKit

@MainActor
final class ProfileTabViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case content
        case readme
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
    private let accountSettingsClient = NodeSeekAccountSettingsClient()
    private let currentAccountStore: CurrentAccountStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = ProfileHeaderView()
    private let refreshControl = UIRefreshControl()
    private var activeUserID: Int?
    private var currentUserID: Int?
    private var account: AccountResponse?
    private var userInfo: NodeSeekUserInfo?
    private var readme: String?
    private var readmeContentHeight: CGFloat = 64
    private var readmeLoadGeneration = 0
    private var hasResolvedReadme = false
    private var readmeLoadFailed = false
    private var loadTask: Task<Void, Never>?
    private var isChangingFollowState = false
    private var followState: NodeSeekFollowState = .notFollowing
    private var hasAppearedOnce = false

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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard hasAppearedOnce else {
            hasAppearedOnce = true
            return
        }
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
        tableView.sectionFooterHeight = 8
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        let bottomInset = AppDisplayScaleSettings.scaled(96)
        tableView.contentInset.bottom = bottomInset
        tableView.verticalScrollIndicatorInsets.bottom = bottomInset
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProfileCell")
        tableView.register(ProfileReadmeCell.self, forCellReuseIdentifier: ProfileReadmeCell.reuseIdentifier)
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableView.refreshControl = refreshControl
        headerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: headerView.preferredHeight)
        tableView.tableHeaderView = headerView
        headerView.onPrivateMessageTapped = { [weak self] in
            self?.openPrivateMessage()
        }
        headerView.onDiscussionsTapped = { [weak self] in
            self?.openContent(.discussions)
        }
        headerView.onCommentsTapped = { [weak self] in
            self?.openContent(.comments)
        }
        headerView.onCoinTapped = { [weak self] in
            self?.openCredit()
        }
        headerView.onStardustTapped = { [weak self] in
            self?.openStardustList()
        }
        headerView.onFansTapped = { [weak self] in
            self?.openFansList()
        }
        headerView.onLevelTapped = { [weak self] in
            self?.openLevelInfo()
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
        readmeLoadGeneration &+= 1
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
                readme = nil
                hasResolvedReadme = true
                headerView.setSignedOut()
                refreshControl.endRefreshing()
                tableView.reloadData()
                return
            }

            if activeUserID != userID {
                readme = nil
                readmeContentHeight = 64
                hasResolvedReadme = false
            }
            activeUserID = userID
            for attempt in 0...1 {
                do {
                    let info = try await userInfoClient.loadUserInfo(userID: userID)
                    guard Task.isCancelled == false else { return }
                    userInfo = info
                    followState = info.followState
                    headerView.configure(
                        userInfo: info,
                        avatarURL: avatarURL(for: userID),
                        isCurrentUser: userID == currentUserID,
                        followState: info.followState
                    )
                    refreshControl.endRefreshing()
                    tableView.reloadData()
                    loadReadme(for: userID)
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
                        headerView.setError(Self.profileErrorMessage(for: error))
                    } else {
                        AppLog.warning(.account, "个人资料刷新失败，保留已展示内容: \(error.localizedDescription)")
                    }
                    // 已登录用户的 readme 独立重载，不因资料接口失败而卡在失败态。
                    if let userID = requestedUserID ?? currentUserID {
                        loadReadme(for: userID)
                    }
                    break
                }
            }
            refreshControl.endRefreshing()
            tableView.reloadData()
        }
    }

    private func loadReadme(for userID: Int) {
        let generation = readmeLoadGeneration
        hasResolvedReadme = false
        readmeContentHeight = 64
        tableView.reloadData()
        Task { [weak self] in
            guard let self else { return }
            do {
                let profile = try await self.accountSettingsClient.loadProfile(userID: userID)
                guard self.readmeLoadGeneration == generation, self.activeUserID == userID else { return }
                let trimmedReadme = profile.readme.trimmingCharacters(in: .whitespacesAndNewlines)
                self.readme = trimmedReadme.isEmpty ? nil : trimmedReadme
                self.readmeLoadFailed = false
            } catch {
                guard self.readmeLoadGeneration == generation, self.activeUserID == userID else { return }
                self.readme = nil
                self.readmeLoadFailed = true
                AppLog.warning(.account, "Readme 加载失败: " + error.localizedDescription)
            }
            self.hasResolvedReadme = true
            self.tableView.reloadData()
        }
    }
    private static func isTemporaryServerError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("503") || message.contains("service unavailable")
    }

    private static func profileErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("429") || message.contains("too many requests") {
            return "请求过于频繁，请稍后下拉刷新。"
        }
        if error is URLError
            || message.contains("network connection was lost")
            || message.contains("network is offline")
            || message.contains("not connected to the internet") {
            return "网络连接已中断，请检查网络后重试。"
        }
        return "暂时无法加载资料，请稍后重试。"
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
        // 下拉重试需同时重置 readme 区，否则失败态文案会停留且无重载入口。
        readmeLoadGeneration &+= 1
        hasResolvedReadme = false
        readmeLoadFailed = false
        readme = nil
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

    private func openCredit() {
        guard let uid = activeUserID else { return }
        navigationController?.pushViewController(
            CreditLedgerViewController(kind: .coin, uid: uid),
            animated: true
        )
    }

    private func openStardustList() {
        guard let uid = activeUserID else { return }
        navigationController?.pushViewController(
            CreditLedgerViewController(kind: .stardust, uid: uid),
            animated: true
        )
    }

    private func openLevelInfo() {
        // 站内没有独立的等级说明页（/about 会 302 到官方介绍帖），
        // 改为本地弹窗展示等级与鸡腿的对应规则（App 内等级计算同源）。
        let message = [
            "Lv1：鸡腿 ≥ 100",
            "Lv2：鸡腿 ≥ 400",
            "Lv3：鸡腿 ≥ 900",
            "Lv4：鸡腿 ≥ 1600",
            "Lv5：鸡腿 ≥ 2500",
            "Lv6：鸡腿 ≥ 3600",
            "",
            "等级由鸡腿数目按开方公式折算，发帖被送鸡腿即可提升。"
        ].joined(separator: "\n")
        let alert = UIAlertController(title: "等级说明", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    private func openFansList() {
        guard let uid = activeUserID else { return }
        navigationController?.pushViewController(
            FansListViewController(fansOf: uid),
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

    private func handleReadmeLink(_ url: URL) {
        let text = url.absoluteString
        if text.contains("/notification"), text.contains("mode=talk") {
            if let toRange = text.range(of: "to=") {
                let tail = text[toRange.upperBound...]
                if let participantID = Int(tail.split(separator: "&").first?.split(separator: "#").first ?? "") {
                    let participantName = userInfo?.username ?? "用户 \(participantID)"
                    navigationController?.pushViewController(
                        PrivateMessageViewController(participantID: participantID, participantName: participantName),
                        animated: true
                    )
                    return
                }
            }
        }
        if isTelegramLink(url) {
            openTelegramLink(url)
            return
        }
        navigationController?.pushViewController(NodeSeekWebViewController(url: url), animated: true)
    }

    private func isTelegramLink(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "tg" { return true }
        let host = url.host?.lowercased()
        return host == "t.me" || host == "telegram.me" || host == "www.t.me" || host == "www.telegram.me"
    }

    private func openTelegramLink(_ url: URL) {
        guard url.scheme?.lowercased() != "tg" else {
            UIApplication.shared.open(url)
            return
        }

        let pathComponents = url.path.split(separator: "/")
        guard let username = pathComponents.first,
              username.hasPrefix("+") == false,
              var components = URLComponents(string: "tg://resolve") else {
            UIApplication.shared.open(url)
            return
        }
        components.queryItems = [URLQueryItem(name: "domain", value: String(username))]
        guard let telegramURL = components.url else {
            UIApplication.shared.open(url)
            return
        }
        UIApplication.shared.open(telegramURL, options: [:]) { opened in
            if opened == false {
                UIApplication.shared.open(url)
            }
        }
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

        let previousFollowState = followState
        let nextFollowState = followState.updatingFollowing(!followState.isFollowing)
        let actionName = nextFollowState.isFollowing ? "关注" : "取消关注"
        isChangingFollowState = true
        followState = nextFollowState
        headerView.setFollowState(nextFollowState)
        headerView.setFollowLoading(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await relationshipClient.setFollowing(userID: userID, following: nextFollowState.isFollowing)
                isChangingFollowState = false
                headerView.setFollowState(nextFollowState)
                headerView.setFollowLoading(false)
            } catch {
                isChangingFollowState = false
                followState = previousFollowState
                headerView.setFollowState(previousFollowState)
                headerView.setFollowLoading(false)
                presentMessage(title: "\(actionName)失败", message: error.localizedDescription)
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
        case .readme:
            return userInfo == nil ? 0 : 1
        case .utility:
            return requestedUserID == nil ? 1 : 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .content:
            return "内容"
        case .readme:
            return userInfo == nil ? nil : "Readme"
        case .utility:
            return requestedUserID == nil ? "应用" : nil
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard Section(rawValue: section) != nil else { return .leastNormalMagnitude }
        return 22
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        8
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard Section(rawValue: indexPath.section) == .readme, readme != nil else {
            return 52
        }
        return readmeContentHeight
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch section {
        case .readme:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ProfileReadmeCell.reuseIdentifier,
                for: indexPath
            ) as? ProfileReadmeCell else {
                return UITableViewCell()
            }
            cell.onLinkTapped = { [weak self] url in
                self?.handleReadmeLink(url)
            }
            cell.onContentHeightChanged = { [weak self] height in
                guard let self, self.readme != nil,
                      abs(self.readmeContentHeight - height) > 1 else {
                    return
                }
                self.readmeContentHeight = height
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
            }
            if let readme {
                cell.configure(markdown: readme)
            } else {
                cell.configureEmptyState(message: readmeLoadFailed ? "Readme 加载失败，下拉重试" : (hasResolvedReadme ? "暂无 Readme" : "正在加载 Readme..."))
            }
            return cell
        case .content, .utility:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileCell", for: indexPath)
            var configuration = cell.defaultContentConfiguration()
            switch section {
            case .content:
                guard let row = ContentRow(rawValue: indexPath.row) else {
                    return UITableViewCell()
                }
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
            case .readme:
                break
            }
            cell.contentConfiguration = configuration
            return cell
        }
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
        case .readme:
            break
        }
    }
}
private final class ProfileHeaderView: UIView {
    /// 根据操作按钮是否可见计算头部高度：头像行 + 简介 + 统计卡 + 操作按钮。
    var preferredHeight: CGFloat {
        actionStack.isHidden ? 192 : 236
    }

    var onHeightNeedsUpdate: (() -> Void)?

    var onPrivateMessageTapped: (() -> Void)?
    var onDiscussionsTapped: (() -> Void)?
    var onCommentsTapped: (() -> Void)?
    var onCoinTapped: (() -> Void)?
    var onStardustTapped: (() -> Void)?
    var onFansTapped: (() -> Void)?
    var onLevelTapped: (() -> Void)?
    var onFollowTapped: (() -> Void)?
    var onTransferTapped: (() -> Void)?

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
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
        statusLabel.text = ""
        setActionsVisible(false)
        setMetrics(Self.placeholderMetrics)
    }

    func setSignedOut() {
        avatarImageView.image = UIImage(systemName: "person.crop.circle.badge.questionmark")
        avatarImageView.tintColor = .secondaryLabel
        nameLabel.text = "未登录"
        statusLabel.text = "登录后可查看个人资料"
        setActionsVisible(false)
        setMetrics(Self.placeholderMetrics)
    }

    func setError(_ message: String) {
        avatarImageView.image = UIImage(systemName: "exclamationmark.circle")
        avatarImageView.tintColor = .systemOrange
        nameLabel.text = "资料加载失败"
        statusLabel.text = message
        setActionsVisible(false)
        setMetrics(Self.placeholderMetrics)
    }

    func configure(userInfo: NodeSeekUserInfo, avatarURL: URL, isCurrentUser: Bool, followState: NodeSeekFollowState) {
        avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarImageView.tintColor = .tertiaryLabel
        ImageLoad.url(avatarURL)
            .toAvatar(requestID: "profile-\(userInfo.userID)")
            .into(avatarImageView)
        let nickname = userInfo.username ?? (isCurrentUser ? "我的账号" : "未知用户")
        // 对照官方 PWA：主标题为昵称，ID 并入简介行。
        nameLabel.text = nickname
        let bio = userInfo.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let highlightedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.systemOrange,
            .font: UIFont.preferredFont(forTextStyle: .footnote)
        ]
        let status = NSMutableAttributedString(
            string: "ID \(userInfo.userID) · Lv \(userInfo.level) · 加入 \(userInfo.joinDays) 天",
            attributes: highlightedAttributes
        )
        if bio.isEmpty == false {
            status.append(NSAttributedString(
                string: " · \(bio)",
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            ))
        }
        statusLabel.attributedText = status
        setActionsVisible(!isCurrentUser)
        setFollowState(followState)
        setMetrics([
            ProfileMetric(
                title: "等级",
                value: "Lv \(userInfo.level)",
                image: UIImage(systemName: "diamond"),
                onTap: isCurrentUser ? onLevelTapped : nil
            ),
            ProfileMetric(
                title: "主题帖",
                value: "\(userInfo.nPost)",
                image: UIImage(systemName: "square.and.pencil"),
                onTap: onDiscussionsTapped
            ),
            ProfileMetric(
                title: "鸡腿",
                value: "\(userInfo.coin)",
                image: ReactionIconRenderer.chickenLeg(pointSize: 18),
                imageTintColor: .secondaryLabel,
                onTap: onCoinTapped
            ),
            ProfileMetric(
                title: "评论数",
                value: "\(userInfo.nComment)",
                image: UIImage(systemName: "text.bubble"),
                onTap: onCommentsTapped
            ),
            ProfileMetric(
                title: "星辰",
                value: "\(userInfo.stardust)",
                image: UIImage(systemName: "wallet.pass"),
                onTap: onStardustTapped
            ),
            ProfileMetric(
                title: "粉丝",
                value: "\(userInfo.fans)",
                image: UIImage(systemName: "dot.radiowaves.left.and.right"),
                onTap: onFansTapped
            )
        ])
    }

    func setFollowLoading(_ isLoading: Bool) {
        followButton.configuration?.showsActivityIndicator = isLoading
        followButton.isEnabled = !isLoading
    }

    func setFollowState(_ followState: NodeSeekFollowState) {
        var configuration = followButton.configuration ?? UIButton.Configuration.gray()
        if followState.isMutual {
            configuration.title = "互相关注"
            configuration.image = UIImage(systemName: "person.2.fill")
            followButton.accessibilityLabel = "互相关注，点击取消关注"
        } else if followState.isFollowing {
            configuration.title = "取消关注"
            configuration.image = UIImage(systemName: "person.badge.minus")
            followButton.accessibilityLabel = "取消关注"
        } else {
            configuration.title = "关注"
            configuration.image = UIImage(systemName: "person.badge.plus")
            followButton.accessibilityLabel = "关注用户"
        }
        configuration.imagePadding = 4
        configuration.baseBackgroundColor = .tertiarySystemFill
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        followButton.configuration = configuration
    }

    private func setupUI() {
        // 与下方 insetGrouped 内容单元保持相同的左右边距。
        layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        // 对照官方 PWA：大头像（圆角方形）、名字与简介、等宽统计卡一行。
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 12

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .preferredFont(forTextStyle: .title3)
        nameLabel.textColor = .label
        nameLabel.textAlignment = .left
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.8
        nameLabel.lineBreakMode = .byTruncatingTail

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .left
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingTail

        metricContainer.translatesAutoresizingMaskIntoConstraints = false
        metricContainer.backgroundColor = .secondarySystemGroupedBackground
        metricContainer.layer.cornerRadius = 10

        metricStack.translatesAutoresizingMaskIntoConstraints = false
        metricStack.axis = .horizontal
        metricStack.distribution = .fillEqually
        metricStack.spacing = 2
        metricContainer.addSubview(metricStack)

        configureActionButton(transferButton, title: "转账", imageName: "arrow.left.arrow.right")
        configureActionButton(privateMessageButton, title: "私信", imageName: "paperplane.fill")
        setFollowState(.notFollowing)
        transferButton.addTarget(self, action: #selector(transferTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)
        privateMessageButton.addTarget(self, action: #selector(privateMessageTapped), for: .touchUpInside)

        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .horizontal
        actionStack.alignment = .fill
        actionStack.distribution = .fillEqually
        actionStack.spacing = 6
        actionStack.addArrangedSubview(transferButton)
        actionStack.addArrangedSubview(followButton)
        actionStack.addArrangedSubview(privateMessageButton)

        addSubview(avatarImageView)
        addSubview(nameLabel)
        addSubview(statusLabel)
        addSubview(metricContainer)
        addSubview(actionStack)
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            avatarImageView.widthAnchor.constraint(equalToConstant: 64),
            avatarImageView.heightAnchor.constraint(equalToConstant: 64),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            metricContainer.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            metricContainer.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            metricContainer.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            metricContainer.heightAnchor.constraint(equalToConstant: 64),

            metricStack.leadingAnchor.constraint(equalTo: metricContainer.leadingAnchor, constant: 4),
            metricStack.trailingAnchor.constraint(equalTo: metricContainer.trailingAnchor, constant: -4),
            metricStack.topAnchor.constraint(equalTo: metricContainer.topAnchor, constant: 6),
            metricStack.bottomAnchor.constraint(equalTo: metricContainer.bottomAnchor, constant: -6),

            actionStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            actionStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            actionStack.topAnchor.constraint(equalTo: metricContainer.bottomAnchor, constant: 10),
            actionStack.heightAnchor.constraint(equalToConstant: 34)
        ])
        setLoading()
    }
    private func configureActionButton(_ button: UIButton, title: String, imageName: String) {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.image = UIImage(systemName: imageName)
        configuration.imagePadding = 4
        configuration.baseBackgroundColor = .tertiarySystemFill
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    private func setActionsVisible(_ isVisible: Bool) {
        actionStack.isHidden = !isVisible
        actionStack.isUserInteractionEnabled = isVisible
        onHeightNeedsUpdate?()
    }

    /// 对照官方 PWA：六个统计项一行等宽排布（card-block 的 space-between 等效实现）。
    private func setMetrics(_ metrics: [ProfileMetric]) {
        metricStack.arrangedSubviews.forEach {
            metricStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        metricStack.axis = .horizontal
        metricStack.distribution = .fillEqually
        metricStack.spacing = 2
        for metric in metrics {
            metricStack.addArrangedSubview(ProfileMetricView(metric: metric))
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

    private static let placeholderMetrics: [ProfileMetric] = [
        ProfileMetric(title: "等级", value: "-", image: UIImage(systemName: "diamond")),
        ProfileMetric(title: "主题帖", value: "-", image: UIImage(systemName: "square.and.pencil")),
        ProfileMetric(
            title: "鸡腿",
            value: "-",
            image: ReactionIconRenderer.chickenLeg(pointSize: 18),
            imageTintColor: .secondaryLabel
        ),
        ProfileMetric(title: "评论数", value: "-", image: UIImage(systemName: "text.bubble")),
        ProfileMetric(title: "星辰", value: "-", image: UIImage(systemName: "wallet.pass")),
        ProfileMetric(title: "粉丝", value: "-", image: UIImage(systemName: "dot.radiowaves.left.and.right"))
    ]
}

private final class ProfileReadmeCell: UITableViewCell, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let reuseIdentifier = "ProfileReadmeCell"
    private static let messageHandlerName = "nodeseekReadme"

    var onLinkTapped: ((URL) -> Void)?
    var onContentHeightChanged: ((CGFloat) -> Void)?

    private lazy var readmeWebView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: Self.messageHandlerName)
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    private let emptyStateLabel = UILabel()
    private var renderedMarkdown: String?
    private var lastReportedContentHeight: CGFloat?
    private var hasFinishedInitialDocument = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        contentView.backgroundColor = .secondarySystemGroupedBackground

        readmeWebView.translatesAutoresizingMaskIntoConstraints = false
        readmeWebView.navigationDelegate = self
        readmeWebView.uiDelegate = self
        readmeWebView.scrollView.isScrollEnabled = false
        readmeWebView.isOpaque = false
        readmeWebView.backgroundColor = .clear
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.adjustsFontForContentSizeCategory = true
        emptyStateLabel.numberOfLines = 2
        emptyStateLabel.isHidden = true
        contentView.addSubview(readmeWebView)
        contentView.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            readmeWebView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            readmeWebView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            readmeWebView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            readmeWebView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            emptyStateLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            emptyStateLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        readmeWebView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
    }

    func configure(markdown: String) {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        emptyStateLabel.isHidden = true
        readmeWebView.isHidden = false
        guard renderedMarkdown != trimmed else { return }
        renderedMarkdown = trimmed
        lastReportedContentHeight = nil
        hasFinishedInitialDocument = false
        readmeWebView.loadHTMLString(Self.htmlDocument(for: trimmed), baseURL: NodeSeekSite.baseURL)
    }

    func configureEmptyState(message: String) {
        renderedMarkdown = nil
        lastReportedContentHeight = nil
        hasFinishedInitialDocument = false
        readmeWebView.stopLoading()
        readmeWebView.isHidden = true
        emptyStateLabel.text = message
        emptyStateLabel.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasFinishedInitialDocument = true
        reportContentHeight()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // 渲染失败时回退纯文本，避免整段空白。
        AppLog.warning(.account, "Readme WebView 渲染失败: \(error.localizedDescription)")
        fallbackToPlainTextIfNeeded()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        AppLog.warning(.account, "Readme WebView 导航失败: \(error.localizedDescription)")
        fallbackToPlainTextIfNeeded()
    }

    private func fallbackToPlainTextIfNeeded() {
        guard let markdown = renderedMarkdown, markdown.isEmpty == false else { return }
        readmeWebView.isHidden = true
        emptyStateLabel.text = markdown
        emptyStateLabel.isHidden = false
        emptyStateLabel.numberOfLines = 0
        report(height: 0)
        onContentHeightChanged?(200)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName,
              let number = message.body as? NSNumber else {
            return
        }
        report(height: number.doubleValue)
    }

    private func reportContentHeight() {
        readmeWebView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] result, _ in
            guard let self, let number = result as? NSNumber else { return }
            self.report(height: number.doubleValue)
        }
    }

    private func report(height rawHeight: Double) {
        let height = max(CGFloat(rawHeight) + 12, 64)
        guard abs((self.lastReportedContentHeight ?? 0) - height) > 1 else { return }
        self.lastReportedContentHeight = height
        self.onContentHeightChanged?(height)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let isMainFrameLink = navigationAction.targetFrame?.isMainFrame == true
        let shouldOpenInsideApp = isMainFrameLink && (
            navigationAction.navigationType == .linkActivated || hasFinishedInitialDocument
        )
        guard shouldOpenInsideApp else {
            decisionHandler(.allow)
            return
        }
        onLinkTapped?(url)
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            onLinkTapped?(url)
        }
        return nil
    }

    private static func htmlDocument(for content: String) -> String {
        let body: String
        if containsStructuralHTML(content) {
            // 还原转义标签后再渲染
            body = content
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;amp;", with: "&amp;")
        } else {
            body = markdownToHTML(content)
        }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"><style>
        :root{color-scheme:light dark}
        body{font-family:-apple-system;font-size:15px;line-height:1.5;margin:0;padding:8px 0;color:#000;word-wrap:break-word;overflow-wrap:break-word}
        @media(prefers-color-scheme:dark){body{color:#fff}}
        a{color:#0A84FF;text-decoration:none} img{display:block;max-width:100%;height:auto;margin:4px 0}.dynamic-embed{display:block;width:100%;height:140px;border:0;margin:4px 0}
        table{max-width:100%;border-collapse:collapse}td,th{border:1px solid #999;padding:4px 8px}
        </style></head><body>\(body)\(heightObserverScript)</body></html>
        """
    }

    private static let structuralHTMLPattern = try! NSRegularExpression(
        pattern: #"<(?:div|section|table|style|script|center|font|h[1-6]|ul|ol|li|blockquote|pre|hr|form|iframe|marquee|tbody|tr|td|th)[\s>]"#,
        options: [.caseInsensitive]
    )

    private static func containsStructuralHTML(_ text: String) -> Bool {
        // 站点接口返回的文本里 HTML 标签常以 &lt; 转义形态出现，
        // 直接原样渲染会整段不可读；出现转义标签时先还原再判定。
        let unescaped = text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        let range = NSRange(unescaped.startIndex..., in: unescaped)
        let hasRealTags = structuralHTMLPattern.firstMatch(in: unescaped, options: [], range: range) != nil
        return hasRealTags
    }

    private static let heightObserverScript = """
    <script>
    (() => {
      const handlerName = 'nodeseekReadme';
      let scheduled = false;
      const report = () => {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => {
          scheduled = false;
          const height = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[handlerName]) {
            window.webkit.messageHandlers[handlerName].postMessage(height);
          }
        });
      };
      window.addEventListener('load', report);
      setTimeout(report, 300);
      setTimeout(report, 1500);
      setTimeout(report, 3000);
      if (document.images && document.images.length) {
        Array.prototype.forEach.call(document.images, (image) => {
          image.addEventListener('load', report);
          image.addEventListener('error', report);
        });
      }
      if (window.MutationObserver) {
        new MutationObserver(report).observe(document.documentElement, { childList: true, subtree: true, attributes: true, characterData: true });
      }
    })();
    </script>
    """

    private static func markdownToHTML(_ markdown: String) -> String {
        var html = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // 围栏代码块先摘出占位，避免内部内容被后续行内转换污染。
        var codeBlocks: [String] = []
        if let fenceRegex = try? NSRegularExpression(pattern: "```[a-zA-Z0-9_+-]*\\n([\\s\\S]*?)```") {
            let nshtml = html as NSString
            let fullRange = NSRange(html.startIndex..., in: html)
            let matches = fenceRegex.matches(in: html, options: [], range: fullRange)
            for match in matches {
                codeBlocks.append(nshtml.substring(with: match.range(at: 1)))
            }
            for match in matches.reversed() {
                let index = matches.firstIndex(of: match) ?? 0
                html = nshtml.replacingCharacters(in: match.range, with: "\u{E000}NSCODE\(index)\u{E001}")
            }
        }

        if let iframeRegex = try? NSRegularExpression(
            pattern: "(?s)&lt;iframe\\b.*?\\bsrc\\s*=\\s*[\\\"'](https://[^\\\"'\\s]+)[\\\"'].*?&gt;(?:\\s*&lt;/iframe&gt;)?",
            options: []
        ) {
            html = iframeRegex.stringByReplacingMatches(
                in: html,
                options: [],
                range: NSRange(html.startIndex..., in: html),
                withTemplate: "<iframe class=\"dynamic-embed\" src=\"$1\" loading=\"lazy\"></iframe>"
            )
        }
        if let imageRegex = try? NSRegularExpression(
            pattern: "!\\[([^\\]]*)\\]\\((https://[^\\s\\)]+)\\)",
            options: []
        ) {
            html = imageRegex.stringByReplacingMatches(
                in: html,
                options: [],
                range: NSRange(html.startIndex..., in: html),
                withTemplate: "<img src=\"$2\" alt=\"$1\">"
            )
        }
        if let linkRegex = try? NSRegularExpression(
            pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)",
            options: []
        ) {
            html = linkRegex.stringByReplacingMatches(
                in: html,
                options: [],
                range: NSRange(html.startIndex..., in: html),
                withTemplate: "<a href=\"$2\">$1</a>"
            )
        }
        html = renderHeaders(in: html)
        if let boldRegex = try? NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*", options: []) {
            html = boldRegex.stringByReplacingMatches(
                in: html,
                options: [],
                range: NSRange(html.startIndex..., in: html),
                withTemplate: "<strong>$1</strong>"
            )
        }
        if let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)", options: []) {
            html = italicRegex.stringByReplacingMatches(
                in: html,
                options: [],
                range: NSRange(html.startIndex..., in: html),
                withTemplate: "<em>$1</em>"
            )
        }
        if let strikeRegex = try? NSRegularExpression(pattern: "~~([^~\\n]+)~~", options: []) {
            html = strikeRegex.stringByReplacingMatches(
                in: html,
                options: [],
                range: NSRange(html.startIndex..., in: html),
                withTemplate: "<del>$1</del>"
            )
        }
        if let inlineCodeRegex = try? NSRegularExpression(pattern: "`([^`\\n]+)`", options: []) {
            html = inlineCodeRegex.stringByReplacingMatches(
                in: html,
                options: [],
                range: NSRange(html.startIndex..., in: html),
                withTemplate: "<code style=\"background:rgba(128,128,128,0.16);padding:1px 4px;border-radius:3px;\">$1</code>"
            )
        }

        // 列表 / 引用 / 分割线：逐行分组后整块输出（不产生内部换行，避免被 <br> 污染）。
        html = Self.renderLineBlocks(in: html)

        html = html.replacingOccurrences(of: "\n", with: "<br>")

        // 还原围栏代码块：<pre> 内保留原始换行。
        for (index, code) in codeBlocks.enumerated() {
            let token = "\u{E000}NSCODE\(index)\u{E001}"
            let escaped = code
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            html = html.replacingOccurrences(
                of: token,
                with: "<pre style=\"background:rgba(128,128,128,0.14);padding:8px;border-radius:6px;overflow-x:auto;white-space:pre\"><code>\(escaped)</code></pre>"
            )
        }
        return html
    }

    /// 把连续的列表行 / 引用行 / 分割线分组渲染为整块 HTML。
    private static func renderLineBlocks(in text: String) -> String {
        var outputLines: [String] = []
        var listBuffer: [String] = []
        var listOrdered = false
        var quoteBuffer: [String] = []

        func flushList() {
            guard listBuffer.isEmpty == false else { return }
            let tag = listOrdered ? "ol" : "ul"
            outputLines.append("<\(tag) style=\"margin:4px 0;padding-left:22px\">"
                + listBuffer.map({ "<li>\($0)</li>" }).joined()
                + "</\(tag)>")
            listBuffer.removeAll()
        }
        func flushQuote() {
            guard quoteBuffer.isEmpty == false else { return }
            outputLines.append("<blockquote style=\"margin:4px 0;padding:4px 10px;border-left:3px solid rgba(128,128,128,0.5);color:inherit\">"
                + quoteBuffer.joined(separator: "<br>")
                + "</blockquote>")
            quoteBuffer.removeAll()
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let trimmed = line.dropFirst(1).trimmingCharacters(in: .whitespaces)
            if line == "---" || line == "***" || line == "___" {
                flushList(); flushQuote()
                outputLines.append("<hr style=\"border:0;border-top:1px solid rgba(128,128,128,0.4)\">")
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushQuote()
                if listBuffer.isEmpty {
                    listOrdered = false
                } else if listOrdered {
                    flushList()
                }
                listBuffer.append(trimmed)
                continue
            }
            if line.hasPrefix("> ") || line == ">" {
                flushList()
                quoteBuffer.append(String(line.dropFirst(line.hasPrefix("> ") ? 2 : 1)))
                continue
            }
            let ordered = Self.matchOrderedListItem(line)
            if let item = ordered {
                flushQuote()
                if listBuffer.isEmpty { listOrdered = true }
                if listOrdered == false, listBuffer.isEmpty == false { flushList() }
                listBuffer.append(item)
                continue
            }
            flushList(); flushQuote()
            outputLines.append(line)
        }
        flushList(); flushQuote()
        return outputLines.joined(separator: "\n")
    }

    private static func matchOrderedListItem(_ line: String) -> String? {
        guard let spaceIndex = line.firstIndex(of: " ") else { return nil }
        let marker = line[line.startIndex..<spaceIndex]
        guard marker.hasSuffix("."), marker.dropLast().allSatisfy(\.isNumber), marker.count <= 4 else { return nil }
        return line[spaceIndex...].dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private static func renderHeaders(in text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
            let body = line.dropFirst(leading.count)
            var level = 0
            for character in body {
                guard character == "#", level < 6 else { break }
                level += 1
            }
            guard level > 0 else { return line }
            let after = body.dropFirst(level)
            guard let first = after.first, first == " " || first == "\t" else { return line }
            let content = after.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            guard content.isEmpty == false else { return line }
            return "\(leading)<h\(level)>\(content)</h\(level)>"
        }.joined(separator: "\n")
    }
}
private struct ProfileMetric {
    let title: String
    let value: String
    let image: UIImage?
    let imageTintColor: UIColor?
    let onTap: (() -> Void)?

    init(
        title: String,
        value: String,
        image: UIImage?,
        imageTintColor: UIColor? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.image = image
        self.imageTintColor = imageTintColor
        self.onTap = onTap
    }

}

private final class ProfileMetricView: UIView {
    private let imageView = UIImageView()
    private let textLabel = UILabel()
    private let valueLabel = UILabel()
    private let contentStack = UIStackView()

    private let imageTintColor: UIColor?
    private let onTap: (() -> Void)?

    init(metric: ProfileMetric) {
        imageTintColor = metric.imageTintColor
        onTap = metric.onTap
        super.init(frame: .zero)
        imageView.image = metric.image
        textLabel.text = metric.title
        valueLabel.text = metric.value
        accessibilityLabel = "\(metric.title) \(metric.value)"
        accessibilityTraits = metric.onTap == nil ? .staticText : .button
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 对照官方 PWA 的 card-item：图标+数值一行居中，标题小字在下，等宽小卡。
    private func setupUI() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = imageTintColor ?? .secondaryLabel
        imageView.contentMode = .scaleAspectFit

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.66
        valueLabel.lineBreakMode = .byTruncatingTail

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = .preferredFont(forTextStyle: .caption2)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.lineBreakMode = .byTruncatingTail

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 3
        contentStack.addArrangedSubview(imageView)
        contentStack.addArrangedSubview(valueLabel)
        contentStack.addArrangedSubview(textLabel)
        addSubview(contentStack)
        if onTap != nil {
            isUserInteractionEnabled = true
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(metricTapped)))
        }
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 1),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -1),
            valueLabel.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
            textLabel.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    @objc private func metricTapped() {
        onTap?()
    }
}
