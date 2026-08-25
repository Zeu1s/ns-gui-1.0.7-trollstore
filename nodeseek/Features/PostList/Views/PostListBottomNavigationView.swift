//
//  PostListBottomNavigationView.swift
//  nodeseek
//

import UIKit

enum PostListBottomNavigationItem: CaseIterable {
    case home
    case history
    case search
    case messages
    case profile

    var title: String {
        switch self {
        case .home: return "首页"
        case .history: return "历史"
        case .search: return "搜索"
        case .messages: return "消息"
        case .profile: return "我的"
        }
    }

    var imageName: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .search: return "magnifyingglass"
        case .messages: return "bell"
        case .profile: return "person"
        }
    }

    var selectedImageName: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.arrow.circlepath"
        case .search: return "magnifyingglass"
        case .messages: return "bell.fill"
        case .profile: return "person.fill"
        }
    }
}

final class PostListBottomNavigationView: UIView {
    private enum Style {
        static let selectedForeground = UIColor.systemOrange
        // 使用中性浅灰底，保留橙色作为选中图标和文字的强调色。
        static let selectedBackground = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return .tertiarySystemFill
            }
            return .systemGray5
        }
    }

    var onItemSelected: ((PostListBottomNavigationItem) -> Void)?
    var onItemDoubleTapped: ((PostListBottomNavigationItem) -> Void)?

    private var buttons: [PostListBottomNavigationItem: UIButton] = [:]
    private let messageUnreadBadge = UILabel()
    private let backgroundBlurView = UIVisualEffectView(effect: nil)
    private let selectionPillView = UIView()
    private var selectedItem: PostListBottomNavigationItem = .home
    private var lastTapItem: PostListBottomNavigationItem?
    private var lastTapTime: TimeInterval = 0
    private var stackLeadingConstraint: NSLayoutConstraint?
    private var stackTrailingConstraint: NSLayoutConstraint?
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?
    private var unreadBadgeMinimumWidthConstraint: NSLayoutConstraint?
    private var unreadBadgeHeightConstraint: NSLayoutConstraint?
    private var unreadBadgeCenterYConstraint: NSLayoutConstraint?
    private var unreadBadgeCenterXConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelectedItem(_ item: PostListBottomNavigationItem) {
        selectedItem = item
        for currentItem in PostListBottomNavigationItem.allCases {
            configure(button: buttons[currentItem], for: currentItem, isSelected: currentItem == item)
        }
        updateSelectionPill(animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSelectionPill(animated: false)
    }

    func setUnreadMessageCount(_ count: Int) {
        let unreadCount = max(0, count)
        messageUnreadBadge.isHidden = unreadCount == 0
        messageUnreadBadge.text = unreadCount > 99 ? "99+" : "\(unreadCount)"
        buttons[.messages]?.accessibilityValue = unreadCount > 0 ? "\(unreadCount) 条未读消息" : nil
    }

    private static let doubleTapInterval: TimeInterval = 0.55

    func setUnreadMessagesVisible(_ isVisible: Bool) {
        setUnreadMessageCount(isVisible ? 1 : 0)
    }

    func refreshDisplayScale() {
        layer.cornerRadius = 0
        selectionPillView.layer.cornerRadius = selectionPillHeight / 2
        messageUnreadBadge.layer.cornerRadius = AppDisplayScaleSettings.scaled(8)
        messageUnreadBadge.font = .systemFont(ofSize: AppDisplayScaleSettings.scaled(10), weight: .semibold)
        stackLeadingConstraint?.constant = AppDisplayScaleSettings.scaled(8)
        stackTrailingConstraint?.constant = -AppDisplayScaleSettings.scaled(8)
        stackTopConstraint?.constant = 0
        stackBottomConstraint?.constant = -AppDisplayScaleSettings.scaled(6)
        unreadBadgeMinimumWidthConstraint?.constant = AppDisplayScaleSettings.scaled(16)
        unreadBadgeHeightConstraint?.constant = AppDisplayScaleSettings.scaled(16)
        unreadBadgeCenterYConstraint?.constant = -AppDisplayScaleSettings.scaled(11)
        unreadBadgeCenterXConstraint?.constant = AppDisplayScaleSettings.scaled(13)
        setSelectedItem(selectedItem)
    }

    private func configureView() {
        accessibilityIdentifier = "post-list-bottom-navigation"
        backgroundColor = .systemBackground
        layer.cornerRadius = 0
        layer.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false

        backgroundBlurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundBlurView)
        backgroundBlurView.backgroundColor = .systemBackground
        NSLayoutConstraint.activate([
            backgroundBlurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundBlurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundBlurView.topAnchor.constraint(equalTo: topAnchor),
            backgroundBlurView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        selectionPillView.backgroundColor = Style.selectedBackground
        selectionPillView.layer.cornerRadius = AppDisplayScaleSettings.scaled(16)
        selectionPillView.isUserInteractionEnabled = false
        selectionPillView.translatesAutoresizingMaskIntoConstraints = true
        selectionPillView.frame = .zero
        addSubview(selectionPillView)

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        for item in PostListBottomNavigationItem.allCases {
            let button = UIButton(type: .system)
            button.tag = itemIndex(item)
            button.accessibilityIdentifier = "post-list-bottom-navigation-\(item.title)"
            button.accessibilityLabel = item.title
            button.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            buttons[item] = button
            stackView.addArrangedSubview(button)
        }

        messageUnreadBadge.backgroundColor = .systemRed
        messageUnreadBadge.textColor = .white
        messageUnreadBadge.font = .systemFont(ofSize: AppDisplayScaleSettings.scaled(10), weight: .semibold)
        messageUnreadBadge.textAlignment = .center
        messageUnreadBadge.layer.cornerRadius = AppDisplayScaleSettings.scaled(8)
        messageUnreadBadge.clipsToBounds = true
        messageUnreadBadge.isHidden = true
        messageUnreadBadge.isUserInteractionEnabled = false
        messageUnreadBadge.isAccessibilityElement = false
        messageUnreadBadge.accessibilityIdentifier = "post-list-bottom-navigation-unread-badge"
        messageUnreadBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageUnreadBadge)

        let stackLeadingConstraint = stackView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: AppDisplayScaleSettings.scaled(8)
        )
        let stackTrailingConstraint = stackView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -AppDisplayScaleSettings.scaled(8)
        )
        let stackTopConstraint = stackView.topAnchor.constraint(
            equalTo: topAnchor,
            constant: 0
        )
        let stackBottomConstraint = stackView.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -AppDisplayScaleSettings.scaled(6)
        )
        let unreadBadgeMinimumWidthConstraint = messageUnreadBadge.widthAnchor.constraint(
            greaterThanOrEqualToConstant: AppDisplayScaleSettings.scaled(16)
        )
        let unreadBadgeHeightConstraint = messageUnreadBadge.heightAnchor.constraint(
            equalToConstant: AppDisplayScaleSettings.scaled(16)
        )
        let unreadBadgeCenterYConstraint: NSLayoutConstraint?
        let unreadBadgeCenterXConstraint: NSLayoutConstraint?
        if let messagesButton = buttons[.messages] {
            unreadBadgeCenterYConstraint = messageUnreadBadge.centerYAnchor.constraint(
                equalTo: messagesButton.centerYAnchor,
                constant: -AppDisplayScaleSettings.scaled(11)
            )
            unreadBadgeCenterXConstraint = messageUnreadBadge.centerXAnchor.constraint(
                equalTo: messagesButton.centerXAnchor,
                constant: AppDisplayScaleSettings.scaled(13)
            )
        } else {
            unreadBadgeCenterYConstraint = nil
            unreadBadgeCenterXConstraint = nil
        }
        self.stackLeadingConstraint = stackLeadingConstraint
        self.stackTrailingConstraint = stackTrailingConstraint
        self.stackTopConstraint = stackTopConstraint
        self.stackBottomConstraint = stackBottomConstraint
        self.unreadBadgeMinimumWidthConstraint = unreadBadgeMinimumWidthConstraint
        self.unreadBadgeHeightConstraint = unreadBadgeHeightConstraint
        self.unreadBadgeCenterYConstraint = unreadBadgeCenterYConstraint
        self.unreadBadgeCenterXConstraint = unreadBadgeCenterXConstraint
        var constraintsToActivate: [NSLayoutConstraint] = [
            stackLeadingConstraint,
            stackTrailingConstraint,
            stackTopConstraint,
            stackBottomConstraint,
            unreadBadgeMinimumWidthConstraint,
            unreadBadgeHeightConstraint
        ]
        if let unreadBadgeCenterYConstraint {
            constraintsToActivate.append(unreadBadgeCenterYConstraint)
        }
        if let unreadBadgeCenterXConstraint {
            constraintsToActivate.append(unreadBadgeCenterXConstraint)
        }
        NSLayoutConstraint.activate(constraintsToActivate)

        setSelectedItem(.home)
    }

    private var selectionPillHeight: CGFloat {
        AppDisplayScaleSettings.scaled(60)
    }

    private func updateSelectionPill(animated: Bool) {
        guard let button = buttons[selectedItem] else { return }
        let target = button.convert(button.bounds, to: self)
        selectionPillView.layer.cornerRadius = selectionPillHeight / 2
        let insetX = AppDisplayScaleSettings.scaled(2)
        let frame = CGRect(
            x: target.minX + insetX,
            // 以按钮内容区为基准略微上移，使图标上方和文字下方的留白对称。
            y: target.midY - AppDisplayScaleSettings.scaled(3) - selectionPillHeight / 2,
            width: target.width - insetX * 2,
            height: selectionPillHeight
        )
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            self.selectionPillView.frame = frame
        }
        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.6,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: apply
            )
        } else {
            apply()
        }
    }

    private func configure(
        button: UIButton?,
        for item: PostListBottomNavigationItem,
        isSelected: Bool
    ) {        guard let button else { return }
        let symbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: AppDisplayScaleSettings.scaled(22),
            weight: isSelected ? .semibold : .regular
        )
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: isSelected ? item.selectedImageName : item.imageName,
            withConfiguration: symbolConfiguration
        )
        configuration.title = item.title
        configuration.imagePlacement = .top
        configuration.imagePadding = AppDisplayScaleSettings.scaled(3)
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: AppDisplayScaleSettings.scaled(4),
            bottom: AppDisplayScaleSettings.scaled(6),
            trailing: AppDisplayScaleSettings.scaled(4)
        )
        configuration.baseForegroundColor = isSelected ? Style.selectedForeground : .label
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(
                ofSize: AppDisplayScaleSettings.scaled(11.5),
                weight: isSelected ? .semibold : .medium
            )
            return outgoing
        }
        button.configuration = configuration
        button.accessibilityTraits = isSelected ? [.button, .selected] : .button
    }

    @objc private func itemTapped(_ sender: UIButton) {
        guard let item = PostListBottomNavigationItem.allCases.first(where: { itemIndex($0) == sender.tag }) else {
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        if lastTapItem == item, now - lastTapTime < Self.doubleTapInterval {
            lastTapItem = nil
            lastTapTime = 0
            setSelectedItem(item)
            onItemDoubleTapped?(item)
            return
        }
        lastTapItem = item
        lastTapTime = now
        setSelectedItem(item)
        onItemSelected?(item)
    }

    private func itemIndex(_ item: PostListBottomNavigationItem) -> Int {
        PostListBottomNavigationItem.allCases.firstIndex { $0.title == item.title } ?? 0
    }
}
