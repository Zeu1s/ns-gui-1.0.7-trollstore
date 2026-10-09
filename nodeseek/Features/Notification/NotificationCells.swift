//
//  NotificationCells.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import UIKit

final class NotificationMentionCell: UITableViewCell {
    static let reuseIdentifier = "NotificationMentionCell"

    private let avatarLoader = AvatarImageLoader.shared
    private let avatarImageView = UIImageView()
    private let unreadIndicatorView = UIView()
    private let profileButton = UIButton(type: .custom)
    private let nameButton = UIButton(type: .system)
    private let levelBadgeLabel = UILabel()
    private let joinDaysBadgeLabel = UILabel()
    private let userInfoLabel = UILabel()
    private let actionLabel = UILabel()
    private let titleLabel = UILabel()
    private let contentLabel = UILabel()
    private let floorLabel = UILabel()
    private let timeLabel = UILabel()
    private let markReadButton = UIButton(type: .system)
    private var onProfileTapped: (() -> Void)?
    private var onMarkReadTapped: (() -> Void)?
    private var onTitleTapped: (() -> Void)?
    private var onReplyTapped: (() -> Void)?
    private var representedID: Int?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if representedID != nil {
            avatarLoader.cancel(on: avatarImageView)
        }
        representedID = nil
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel
        unreadIndicatorView.isHidden = true
        nameButton.setTitle(nil, for: .normal)
        levelBadgeLabel.text = nil
        levelBadgeLabel.isHidden = true
        joinDaysBadgeLabel.text = nil
        joinDaysBadgeLabel.isHidden = true
        userInfoLabel.text = nil
        userInfoLabel.isHidden = true
        actionLabel.text = nil
        titleLabel.text = nil
        contentLabel.text = nil
        contentLabel.isHidden = true
        floorLabel.text = nil
        timeLabel.text = nil
        markReadButton.isHidden = true
        onProfileTapped = nil
        onMarkReadTapped = nil
        onTitleTapped = nil
        onReplyTapped = nil
    }

    func configure(
        record: NodeSeekNotificationRecord,
        tab: NodeSeekNotificationTab,
        timeText: String,
        onProfileTapped: @escaping () -> Void,
        onMarkReadTapped: @escaping () -> Void,
        onTitleTapped: @escaping () -> Void,
        onReplyTapped: @escaping () -> Void
    ) {
        representedID = record.id
        self.onProfileTapped = onProfileTapped
        self.onMarkReadTapped = onMarkReadTapped
        self.onTitleTapped = onTitleTapped
        self.onReplyTapped = onReplyTapped
        nameButton.setTitle(record.commenterName, for: .normal)
        actionLabel.text = tab == .atMe ? "在帖子中@了我" : "回复了我的帖子"
        titleLabel.text = record.title
        let rawContent = record.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = rawContent.isEmpty ? "" : UserCommentPreview.text(from: rawContent)
        contentLabel.attributedText = preview.isEmpty ? nil : UserContentText.commentPreview(preview)
        contentLabel.isHidden = preview.isEmpty
        floorLabel.text = "#\(record.floorID) 楼"
        let userInfoStore = NodeSeekUserInfoStore.shared
        configureUserInfo(userInfoStore.badgeText(for: record.profileURL))
        userInfoStore.requestBadge(for: record.profileURL)
        configureUnreadIndicator(isUnread: record.displayUnreadCount > 0)
        accessibilityValue = record.isViewed ? nil : "未读"
        markReadButton.isHidden = record.isViewed
        accessibilityLabel = [
            record.commenterName,
            levelBadgeLabel.text,
            joinDaysBadgeLabel.text,
            userInfoLabel.text,
            actionLabel.text,
            preview.isEmpty ? nil : preview,
            record.title,
            timeText
        ].compactMap { $0 }.joined(separator: " ")

        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel
        ImageLoad.url(record.avatarURL)
            .toAvatar(requestID: "\(record.commenterID)")
            .into(avatarImageView)
    }

    private func setupUI() {
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 8
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel

        unreadIndicatorView.backgroundColor = .systemRed
        unreadIndicatorView.layer.cornerRadius = 4
        unreadIndicatorView.clipsToBounds = true
        unreadIndicatorView.isHidden = true
        unreadIndicatorView.isAccessibilityElement = false
        unreadIndicatorView.accessibilityIdentifier = "notification-sender-unread-indicator"
        unreadIndicatorView.setContentHuggingPriority(.required, for: .horizontal)
        unreadIndicatorView.setContentCompressionResistancePriority(.required, for: .horizontal)

        profileButton.translatesAutoresizingMaskIntoConstraints = false
        profileButton.accessibilityLabel = "打开用户主页"
        profileButton.addTarget(self, action: #selector(profileTapped), for: .touchUpInside)

        nameButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        nameButton.titleLabel?.adjustsFontForContentSizeCategory = true
        nameButton.contentHorizontalAlignment = .leading
        nameButton.setTitleColor(AppTypography.primaryTextColor, for: .normal)
        nameButton.addTarget(self, action: #selector(profileTapped), for: .touchUpInside)
        nameButton.setContentHuggingPriority(.required, for: .horizontal)
        nameButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        actionLabel.font = .preferredFont(forTextStyle: .subheadline)
        actionLabel.textColor = .secondaryLabel
        actionLabel.adjustsFontForContentSizeCategory = true
        actionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        userInfoLabel.font = .preferredFont(forTextStyle: .caption2)
        userInfoLabel.textColor = .tertiaryLabel
        userInfoLabel.adjustsFontForContentSizeCategory = true
        userInfoLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        levelBadgeLabel.font = .preferredFont(forTextStyle: .caption2)
        levelBadgeLabel.textColor = .white
        levelBadgeLabel.backgroundColor = .systemGreen
        levelBadgeLabel.textAlignment = .center
        levelBadgeLabel.layer.cornerRadius = 3
        levelBadgeLabel.clipsToBounds = true
        levelBadgeLabel.adjustsFontForContentSizeCategory = true
        levelBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        levelBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        joinDaysBadgeLabel.font = .preferredFont(forTextStyle: .caption2)
        joinDaysBadgeLabel.textColor = .white
        joinDaysBadgeLabel.backgroundColor = .systemGreen
        joinDaysBadgeLabel.textAlignment = .center
        joinDaysBadgeLabel.layer.cornerRadius = 3
        joinDaysBadgeLabel.clipsToBounds = true
        joinDaysBadgeLabel.adjustsFontForContentSizeCategory = true
        joinDaysBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        joinDaysBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = AppTypography.primaryTextColor
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleTapped)))

        contentLabel.font = .preferredFont(forTextStyle: .subheadline)
        contentLabel.textColor = .secondaryLabel
        contentLabel.adjustsFontForContentSizeCategory = true
        contentLabel.numberOfLines = 2
        contentLabel.isHidden = true
        contentLabel.isUserInteractionEnabled = true
        let contentTap = UITapGestureRecognizer(target: self, action: #selector(replyTapped))
        contentLabel.addGestureRecognizer(contentTap)

        timeLabel.font = .preferredFont(forTextStyle: .caption1)
        timeLabel.textColor = .secondaryLabel
        timeLabel.adjustsFontForContentSizeCategory = true

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        markReadButton.translatesAutoresizingMaskIntoConstraints = false
        markReadButton.setImage(UIImage(systemName: "envelope.open", withConfiguration: symbolConfiguration), for: .normal)
        markReadButton.tintColor = .secondaryLabel
        markReadButton.accessibilityLabel = "标为已读"
        markReadButton.accessibilityIdentifier = "notification-mark-read-button"
        markReadButton.addTarget(self, action: #selector(markReadTapped), for: .touchUpInside)

        let metaRow = UIStackView(arrangedSubviews: [nameButton, unreadIndicatorView, levelBadgeLabel, joinDaysBadgeLabel, userInfoLabel, actionLabel])
        metaRow.translatesAutoresizingMaskIntoConstraints = false
        metaRow.axis = .horizontal
        metaRow.alignment = .center
        metaRow.spacing = 3

        floorLabel.font = .preferredFont(forTextStyle: .caption2)
        floorLabel.textColor = .systemOrange
        floorLabel.adjustsFontForContentSizeCategory = true
        floorLabel.isUserInteractionEnabled = true
        let floorTap = UITapGestureRecognizer(target: self, action: #selector(replyTapped))
        floorLabel.addGestureRecognizer(floorTap)

        let textStack = UIStackView(arrangedSubviews: [metaRow, titleLabel, contentLabel, floorLabel, timeLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 2

        contentView.addSubview(avatarImageView)
        contentView.addSubview(profileButton)
        contentView.addSubview(textStack)
        contentView.addSubview(markReadButton)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -13),

            unreadIndicatorView.widthAnchor.constraint(equalToConstant: 8),
            unreadIndicatorView.heightAnchor.constraint(equalToConstant: 8),

            profileButton.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor),
            profileButton.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor),
            profileButton.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            profileButton.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor),

            markReadButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            markReadButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            markReadButton.widthAnchor.constraint(equalToConstant: 36),
            markReadButton.heightAnchor.constraint(equalToConstant: 36),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: markReadButton.leadingAnchor, constant: -8),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11)
        ])
    }

    @objc private func profileTapped() {
        onProfileTapped?()
    }

    @objc private func markReadTapped() {
        onMarkReadTapped?()
    }

    @objc private func titleTapped() {
        onTitleTapped?()
    }

    @objc private func replyTapped() {
        onReplyTapped?()
    }

    private func configureUserInfo(_ badgeText: String?) {
        var parts = badgeText?
            .split(separator: "·")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        guard parts.isEmpty == false else {
            levelBadgeLabel.isHidden = true
            joinDaysBadgeLabel.isHidden = true
            userInfoLabel.text = nil
            userInfoLabel.isHidden = true
            return
        }

        if let levelIndex = parts.firstIndex(where: Self.isLevelBadge) {
            levelBadgeLabel.text = " \(parts.remove(at: levelIndex)) "
            levelBadgeLabel.isHidden = false
        } else {
            levelBadgeLabel.text = nil
            levelBadgeLabel.isHidden = true
        }
        if let joinDaysIndex = parts.firstIndex(where: Self.isJoinDaysBadge) {
            joinDaysBadgeLabel.text = " \(parts.remove(at: joinDaysIndex)) "
            joinDaysBadgeLabel.isHidden = false
        } else {
            joinDaysBadgeLabel.text = nil
            joinDaysBadgeLabel.isHidden = true
        }
        let remaining = parts.joined(separator: " · ")
        userInfoLabel.text = remaining.isEmpty ? nil : remaining
        userInfoLabel.isHidden = userInfoLabel.text?.isEmpty != false
    }

    private static func isLevelBadge(_ text: String) -> Bool {
        text.range(of: "lv", options: .caseInsensitive) != nil
            || text.contains("等级")
            || text.range(of: "level", options: .caseInsensitive) != nil
    }

    private static func isJoinDaysBadge(_ text: String) -> Bool {
        text.contains("加入")
            || text.range(of: "day", options: .caseInsensitive) != nil
            || (text.hasSuffix("天") && text.rangeOfCharacter(from: .decimalDigits) != nil)
    }

    private func configureUnreadIndicator(isUnread: Bool) {
        unreadIndicatorView.isHidden = !isUnread
    }
}

final class NotificationMessageCell: UITableViewCell {
    static let reuseIdentifier = "NotificationMessageCell"

    private let avatarLoader = AvatarImageLoader.shared
    private let avatarImageView = UIImageView()
    private let unreadIndicatorView = UIView()
    private let nameLabel = UILabel()
    private let contentLabel = UILabel()
    private let timeLabel = UILabel()
    private var representedID: Int?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        selectionStyle = .default
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if representedID != nil {
            avatarLoader.cancel(on: avatarImageView)
        }
        representedID = nil
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel
        unreadIndicatorView.isHidden = true
        nameLabel.text = nil
        contentLabel.text = nil
        timeLabel.text = nil
    }

    func configure(
        record: NodeSeekMessageConversationRecord,
        currentUserID: Int?,
        timeText: String
    ) {
        representedID = record.maxID
        let participantName = record.participantName(currentUserID: currentUserID)
        nameLabel.text = participantName
        contentLabel.text = record.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        timeLabel.text = timeText
        configureUnreadIndicator(isUnread: record.displayUnreadCount > 0)
        accessibilityValue = record.isViewed ? nil : "未读"
        accessibilityLabel = [participantName, contentLabel.text, timeText]
            .compactMap { $0 }
            .joined(separator: " ")

        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel
        ImageLoad.url(record.participantAvatarURL(currentUserID: currentUserID))
            .toAvatar(requestID: "\(record.participantID(currentUserID: currentUserID))")
            .into(avatarImageView)
    }

    private func setupUI() {
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 8
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel

        unreadIndicatorView.backgroundColor = .systemRed
        unreadIndicatorView.layer.cornerRadius = 4
        unreadIndicatorView.clipsToBounds = true
        unreadIndicatorView.isHidden = true
        unreadIndicatorView.isAccessibilityElement = false
        unreadIndicatorView.accessibilityIdentifier = "notification-sender-unread-indicator"
        unreadIndicatorView.setContentHuggingPriority(.required, for: .horizontal)
        unreadIndicatorView.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.textColor = .label
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        contentLabel.font = .preferredFont(forTextStyle: .subheadline)
        contentLabel.textColor = .secondaryLabel
        contentLabel.adjustsFontForContentSizeCategory = true
        contentLabel.numberOfLines = 2

        timeLabel.font = .preferredFont(forTextStyle: .caption1)
        timeLabel.textColor = .secondaryLabel
        timeLabel.adjustsFontForContentSizeCategory = true

        let nameRow = UIStackView(arrangedSubviews: [nameLabel, unreadIndicatorView])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 5

        let textStack = UIStackView(arrangedSubviews: [nameRow, contentLabel, timeLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4

        contentView.addSubview(avatarImageView)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -13),

            unreadIndicatorView.widthAnchor.constraint(equalToConstant: 8),
            unreadIndicatorView.heightAnchor.constraint(equalToConstant: 8),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11)
        ])
    }

    private func configureUnreadIndicator(isUnread: Bool) {
        unreadIndicatorView.isHidden = !isUnread
    }
}
