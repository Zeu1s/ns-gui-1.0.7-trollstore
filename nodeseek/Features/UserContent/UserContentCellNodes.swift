//
//  UserContentCellNodes.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import AsyncDisplayKit
import UIKit

final class UserContentSkeletonCellNode: ASCellNode {
    private enum Layout {
        static let contentInset = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        static let titleHeight: CGFloat = 18
        static let metaHeight: CGFloat = 13
    }

    private let titlePlaceholder = ASDisplayNode()
    private let metaPlaceholder = ASDisplayNode()
    private let extraPlaceholder = ASDisplayNode()

    private lazy var placeholderNodes = [
        titlePlaceholder,
        metaPlaceholder,
        extraPlaceholder
    ]

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear
        configurePlaceholders()
    }

    override func didLoad() {
        super.didLoad()
        startPulseAnimation()
    }

    override func didEnterVisibleState() {
        super.didEnterVisibleState()
        startPulseAnimation()
    }

    override func didExitVisibleState() {
        super.didExitVisibleState()
        stopPulseAnimation()
    }

    deinit {
        stopPulseAnimation()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let bottomStack = ASStackLayoutSpec.horizontal()
        bottomStack.spacing = 8
        bottomStack.children = [metaPlaceholder, extraPlaceholder]

        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = 9
        stack.children = [titlePlaceholder, bottomStack]
        return ASInsetLayoutSpec(insets: Layout.contentInset, child: stack)
    }

    private func configurePlaceholders() {
        titlePlaceholder.style.height = ASDimension(unit: .points, value: Layout.titleHeight)
        titlePlaceholder.style.width = ASDimension(unit: .fraction, value: 0.82)
        titlePlaceholder.cornerRadius = 5

        metaPlaceholder.style.height = ASDimension(unit: .points, value: Layout.metaHeight)
        metaPlaceholder.style.width = ASDimension(unit: .fraction, value: 0.28)
        metaPlaceholder.cornerRadius = 4

        extraPlaceholder.style.height = ASDimension(unit: .points, value: Layout.metaHeight)
        extraPlaceholder.style.width = ASDimension(unit: .fraction, value: 0.18)
        extraPlaceholder.cornerRadius = 4

        for node in placeholderNodes {
            node.backgroundColor = .systemGray5
            node.clipsToBounds = true
        }
    }

    private func startPulseAnimation() {
        for node in placeholderNodes {
            guard node.layer.animation(forKey: "user_content_skeleton_pulse") == nil else { continue }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.45
            animation.duration = 0.8
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.layer.add(animation, forKey: "user_content_skeleton_pulse")
        }
    }

    private func stopPulseAnimation() {
        for node in placeholderNodes {
            node.layer.removeAnimation(forKey: "user_content_skeleton_pulse")
        }
    }
}

final class UserDiscussionCellNode: ASCellNode {
    private let titleNode = ASTextNode()

    init(record: UserDiscussionRecord) {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .default
        titleNode.maximumNumberOfLines = 2
        titleNode.attributedText = UserContentText.title(record.title)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASInsetLayoutSpec(insets: UIEdgeInsets(top: 13, left: 18, bottom: 13, right: 18), child: titleNode)
    }
}

final class UserCollectionCellNode: ASCellNode {
    private let titleNode = ASTextNode()

    init(record: UserCollectionRecord) {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .default
        titleNode.maximumNumberOfLines = 2
        titleNode.attributedText = UserContentText.title(record.title)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASInsetLayoutSpec(insets: UIEdgeInsets(top: 13, left: 18, bottom: 13, right: 18), child: titleNode)
    }
}

final class UserCommentCellNode: ASCellNode {
    private let titleNode = ASTextNode()
    private let textNode = ASTextNode()
    private let onOpenPost: () -> Void
    private let onOpenComment: () -> Void

    init(
        record: UserCommentRecord,
        onOpenPost: @escaping () -> Void,
        onOpenComment: @escaping () -> Void
    ) {
        self.onOpenPost = onOpenPost
        self.onOpenComment = onOpenComment
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear
        titleNode.maximumNumberOfLines = 2
        titleNode.attributedText = UserContentText.title(record.title)
        titleNode.accessibilityLabel = "打开主题：\(record.title)"
        textNode.maximumNumberOfLines = 2
        textNode.attributedText = Self.commentText(record.text)
        textNode.accessibilityLabel = "打开回复 #\(record.floorID)"
    }

    override func didLoad() {
        super.didLoad()
        titleNode.isUserInteractionEnabled = true
        textNode.isUserInteractionEnabled = true
        titleNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPostTapped)))
        textNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openCommentTapped)))
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = 5
        textStack.children = [titleNode, textNode]
        return ASInsetLayoutSpec(insets: UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18), child: textStack)
    }

    private static func commentText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text.trimmingCharacters(in: .whitespacesAndNewlines),
            attributes: [
                .font: PostListCellStyle.Typography.metadataFont,
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
    }

    @objc private func openPostTapped() {
        onOpenPost()
    }

    @objc private func openCommentTapped() {
        onOpenComment()
    }
}

enum UserContentText {
    static func title(_ title: String) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: PostListCellStyle.Typography.titleFont,
                .foregroundColor: UIColor.label
            ]
        )
    }
}
