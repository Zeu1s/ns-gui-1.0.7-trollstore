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
        // 对应 1.3 版底栏选中项的浅米色底。
        static let selectedBackground = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return .systemOrange.withAlphaComponent(0.28)
            }
            return UIColor(red: 0.988, green: 0.906, blue: 0.765, alpha: 1)
        }
    }

    var onItemSelected: ((PostListBottomNavigationItem) -> Void)?
    var onItemDoubleTapped: ((PostListBottomNavigationItem) -> Void)?

    private var buttons: [PostListBottomNavigationItem: UIButton] = [:]
    private let messageUnreadBadge = UIView()
    private let backgroundBlurView = UIVisualEffectView(effect: nil)
    private let selectionPillView = UIView()
    private var selectedItem: PostListBottomNavigationItem = .home
    private var lastTapItem: PostListBottomNavigationItem?
    private var lastTapTime: TimeInterval = 0
    private var stackLeadingConstraint: NSLayoutConstraint?
    private var stackTrailingConstraint: NSLayoutConstraint?
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?
    private var unreadBadgeWidthConstraint: NSLayoutConstraint?
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

    func setUnreadMessagesVisible(_ isVisible: Bool) {
        messageUnreadBadge.isHidden = !isVisible
        buttons[.messages]?.accessibilityValue = isVisible ? "有未读消息" : nil
    }

    func refreshDisplayScale() {
        layer.cornerRadius = 0
        selectionPillView.layer.cornerRadius = selectionPillHeight / 2
        messageUnreadBadge.layer.cornerRadius = AppDisplayScaleSettings.scaled(6)
        stackLeadingConstraint?.constant = AppDisplayScaleSettings.scaled(8)
        stackTrailingConstraint?.constant = -AppDisplayScaleSettings.scaled(8)
        stackTopConstraint?.constant = AppDisplayScaleSettings.scaled(2)
        stackBottomConstraint?.constant = -AppDisplayScaleSettings.scaled(2)
        unreadBadgeWidthConstraint?.constant = AppDisplayScaleSettings.scaled(12)
        unreadBadgeHeightConstraint?.constant = AppDisplayScaleSettings.scaled(12)
        unreadBadgeCenterYConstraint?.constant = -AppDisplayScaleSettings.scaled(10)
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
        messageUnreadBadge.layer.cornerRadius = AppDisplayScaleSettings.scaled(6)
        messageUnreadBadge.isHidden = true
        messageUnreadBadge.isUserInteractionEnabled = false
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
            constant: AppDisplayScaleSettings.scaled(2)
        )
        let stackBottomConstraint = stackView.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -AppDisplayScaleSettings.scaled(2)
        )
        let unreadBadgeWidthConstraint = messageUnreadBadge.widthAnchor.constraint(
            equalToConstant: AppDisplayScaleSettings.scaled(12)
        )
        let unreadBadgeHeightConstraint = messageUnreadBadge.heightAnchor.constraint(
            equalToConstant: AppDisplayScaleSettings.scaled(12)
        )
        let unreadBadgeCenterYConstraint = messageUnreadBadge.centerYAnchor.constraint(
            equalTo: buttons[.messages]!.centerYAnchor,
            constant: -AppDisplayScaleSettings.scaled(10)
        )
        let unreadBadgeCenterXConstraint = messageUnreadBadge.centerXAnchor.constraint(
            equalTo: buttons[.messages]!.centerXAnchor,
            constant: AppDisplayScaleSettings.scaled(13)
        )
        self.stackLeadingConstraint = stackLeadingConstraint
        self.stackTrailingConstraint = stackTrailingConstraint
        self.stackTopConstraint = stackTopConstraint
        self.stackBottomConstraint = stackBottomConstraint
        self.unreadBadgeWidthConstraint = unreadBadgeWidthConstraint
        self.unreadBadgeHeightConstraint = unreadBadgeHeightConstraint
        self.unreadBadgeCenterYConstraint = unreadBadgeCenterYConstraint
        self.unreadBadgeCenterXConstraint = unreadBadgeCenterXConstraint
        NSLayoutConstraint.activate([
            stackLeadingConstraint,
            stackTrailingConstraint,
            stackTopConstraint,
            stackBottomConstraint,
            unreadBadgeWidthConstraint,
            unreadBadgeHeightConstraint,
            unreadBadgeCenterYConstraint,
            unreadBadgeCenterXConstraint
        ])
        setSelectedItem(.home)
    }

    private var selectionPillHeight: CGFloat {
        AppDisplayScaleSettings.scaled(40)
    }

    private func updateSelectionPill(animated: Bool) {
        guard let button = buttons[selectedItem] else { return }
        let target = button.convert(button.bounds, to: self)
        selectionPillView.layer.cornerRadius = selectionPillHeight / 2
        let insetX = AppDisplayScaleSettings.scaled(8)
        let frame = CGRect(
            x: target.minX + insetX,
            y: target.midY - selectionPillHeight / 2,
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
            pointSize: AppDisplayScaleSettings.scaled(19),
            weight: isSelected ? .semibold : .regular
        )
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: isSelected ? item.selectedImageName : item.imageName,
            withConfiguration: symbolConfiguration
        )
        configuration.title = item.title
        configuration.imagePlacement = .top
        configuration.imagePadding = AppDisplayScaleSettings.scaled(2)
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: AppDisplayScaleSettings.scaled(3),
            leading: AppDisplayScaleSettings.scaled(4),
            bottom: AppDisplayScaleSettings.scaled(3),
            trailing: AppDisplayScaleSettings.scaled(4)
        )
        configuration.baseForegroundColor = isSelected ? Style.selectedForeground : .label
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(
                ofSize: AppDisplayScaleSettings.scaled(10.5),
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
        if lastTapItem == item, now - lastTapTime < 0.4 {
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
