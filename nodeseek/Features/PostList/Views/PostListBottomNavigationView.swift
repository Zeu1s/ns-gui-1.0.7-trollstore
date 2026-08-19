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
    var onItemSelected: ((PostListBottomNavigationItem) -> Void)?

    private var buttons: [PostListBottomNavigationItem: UIButton] = [:]
    private let messageUnreadBadge = UIView()
    private var selectedItem: PostListBottomNavigationItem = .home

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
    }

    func setUnreadMessagesVisible(_ isVisible: Bool) {
        messageUnreadBadge.isHidden = !isVisible
        buttons[.messages]?.accessibilityValue = isVisible ? "有未读消息" : nil
    }

    func refreshDisplayScale() {
        setSelectedItem(selectedItem)
    }

    private func configureView() {
        accessibilityIdentifier = "post-list-bottom-navigation"
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

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
        messageUnreadBadge.layer.cornerRadius = 4
        messageUnreadBadge.isHidden = true
        messageUnreadBadge.isUserInteractionEnabled = false
        messageUnreadBadge.accessibilityIdentifier = "post-list-bottom-navigation-unread-badge"
        messageUnreadBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageUnreadBadge)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),

            messageUnreadBadge.widthAnchor.constraint(equalToConstant: 8),
            messageUnreadBadge.heightAnchor.constraint(equalToConstant: 8),
            messageUnreadBadge.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            messageUnreadBadge.centerXAnchor.constraint(equalTo: buttons[.messages]!.centerXAnchor, constant: 12)
        ])
        setSelectedItem(.home)
    }

    private func configure(
        button: UIButton?,
        for item: PostListBottomNavigationItem,
        isSelected: Bool
    ) {
        guard let button else { return }
        let symbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 21,
            weight: isSelected ? .semibold : .regular
        )
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: isSelected ? item.selectedImageName : item.imageName,
            withConfiguration: symbolConfiguration
        )
        configuration.title = item.title
        configuration.imagePlacement = .top
        configuration.imagePadding = 3
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
        configuration.baseForegroundColor = isSelected ? .systemOrange : .label
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(
                ofSize: 14 * AppDisplayScaleSettings.shared.scale,
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
        setSelectedItem(item)
        onItemSelected?(item)
    }

    private func itemIndex(_ item: PostListBottomNavigationItem) -> Int {
        PostListBottomNavigationItem.allCases.firstIndex { $0.title == item.title } ?? 0
    }
}
