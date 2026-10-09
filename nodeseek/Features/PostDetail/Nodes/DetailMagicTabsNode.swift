//
//  DetailMagicTabsNode.swift
//  nodeseek
//

import AsyncDisplayKit
import UIKit

/// NodeSeek `nsk-magic-tabs` 的原生展示，适用于 NodeQuality 图文报告。
final class DetailMagicTabsNode: ASDisplayNode {
    struct Tab {
        let title: String
        let bodyNodes: [ASDisplayNode]
    }

    private enum Layout {
        static let spacing: CGFloat = 8
        static let contentInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }

    private let tabs: [Tab]
    private let titleNodes: [ASButtonNode]
    private let onLayoutInvalidated: () -> Void
    private let onSelectionChanged: (Int) -> Void
    private let contentBackgroundNode = ASDisplayNode()
    private var selectedIndex: Int

    init(
        tabs: [Tab],
        initialSelectedIndex: Int = 0,
        onSelectionChanged: @escaping (Int) -> Void = { _ in },
        onLayoutInvalidated: @escaping () -> Void
    ) {
        self.tabs = tabs
        self.onLayoutInvalidated = onLayoutInvalidated
        self.onSelectionChanged = onSelectionChanged
        self.selectedIndex = min(max(initialSelectedIndex, 0), max(tabs.count - 1, 0))
        self.titleNodes = tabs.map { tab in
            let node = ASButtonNode()
            node.accessibilityLabel = "切换到 \(tab.title)"
            return node
        }
        super.init()
        automaticallyManagesSubnodes = true
        style.flexGrow = 1
        style.flexShrink = 1
        contentBackgroundNode.backgroundColor = .secondarySystemBackground
        contentBackgroundNode.cornerRadius = 8
        titleNodes.forEach { $0.addTarget(self, action: #selector(tabTapped(_:)), forControlEvents: .touchUpInside) }
        configureTitleNodes()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let titleStack = ASStackLayoutSpec.horizontal()
        titleStack.spacing = 4
        titleStack.alignItems = .stretch
        titleNodes.forEach {
            $0.style.flexGrow = 1
            $0.style.flexShrink = 1
        }
        titleStack.children = titleNodes

        let selectedNodes = tabs[selectedIndex].bodyNodes
        let body = ASStackLayoutSpec.vertical()
        body.spacing = Layout.spacing
        body.children = selectedNodes
        body.style.flexGrow = 1
        body.style.flexShrink = 1
        let content = ASInsetLayoutSpec(insets: Layout.contentInset, child: body)
        let contentCard = ASBackgroundLayoutSpec(child: content, background: contentBackgroundNode)

        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = Layout.spacing
        stack.children = [titleStack, contentCard]
        return stack
    }

    @objc private func tabTapped(_ sender: ASButtonNode) {
        guard let index = titleNodes.firstIndex(where: { $0 === sender }), selectedIndex != index else { return }
        selectedIndex = index
        onSelectionChanged(index)
        configureTitleNodes()
        setNeedsLayout()
        onLayoutInvalidated()
    }

    private func configureTitleNodes() {
        for (index, node) in titleNodes.enumerated() {
            let isSelected = index == selectedIndex
            node.setAttributedTitle(
                NSAttributedString(
                    string: tabs[index].title,
                    attributes: [
                        .font: UIFont.preferredFont(forTextStyle: .subheadline),
                        .foregroundColor: isSelected ? UIColor.systemOrange : UIColor.secondaryLabel
                    ]
                ),
                for: .normal
            )
            node.contentEdgeInsets = UIEdgeInsets(top: 7, left: 6, bottom: 7, right: 6)
            node.backgroundColor = isSelected ? UIColor.systemOrange.withAlphaComponent(0.14) : .clear
            node.cornerRadius = 6
            node.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }
}
