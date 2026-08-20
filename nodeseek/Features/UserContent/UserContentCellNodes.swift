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

class UserContentPostCardCellNode: ASCellNode {
    private enum Layout {
        static let avatarSize: CGFloat = 48
        static let spacing: CGFloat = 12
        static let contentInset = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 12)
    }

    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let metadataNode = ASTextNode()

    init(title: String, metadata: String, systemImageName: String, tintColor: UIColor) {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .default

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        iconNode.image = UIImage(systemName: systemImageName, withConfiguration: symbolConfiguration)?
            .withTintColor(tintColor, renderingMode: .alwaysOriginal)
        iconNode.backgroundColor = tintColor.withAlphaComponent(0.12)
        iconNode.cornerRadius = PostListCellStyle.Avatar.cornerRadius
        iconNode.contentMode = .center
        iconNode.style.preferredSize = CGSize(width: Layout.avatarSize, height: Layout.avatarSize)

        titleNode.maximumNumberOfLines = 2
        titleNode.truncationMode = .byTruncatingTail
        titleNode.attributedText = UserContentText.title(title)

        metadataNode.maximumNumberOfLines = 1
        metadataNode.truncationMode = .byTruncatingTail
        metadataNode.attributedText = UserContentText.metadata(metadata)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        titleNode.style.flexShrink = 1
        metadataNode.style.flexShrink = 1
        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = 3
        textStack.children = [titleNode, metadataNode]
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = Layout.spacing
        contentStack.alignItems = .center
        contentStack.children = [iconNode, textStack]
        return ASInsetLayoutSpec(insets: Layout.contentInset, child: contentStack)
    }
}

final class UserDiscussionCellNode: UserContentPostCardCellNode {
    init(record: UserDiscussionRecord) {
        super.init(
            title: record.title,
            metadata: "主题帖  ·  #\(record.rank)",
            systemImageName: "doc.text",
            tintColor: .systemOrange
        )
    }
}

final class UserCollectionCellNode: UserContentPostCardCellNode {
    init(record: UserCollectionRecord) {
        super.init(
            title: record.title,
            metadata: "收藏的主题  ·  #\(record.rank)",
            systemImageName: "bookmark",
            tintColor: .systemOrange
        )
    }
}

final class UserCommentCellNode: ASCellNode {
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let textNode = ASTextNode()
    private let floorNode = ASTextNode()
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
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        iconNode.image = UIImage(systemName: "text.bubble", withConfiguration: symbolConfiguration)?
            .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
        iconNode.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        iconNode.cornerRadius = PostListCellStyle.Avatar.cornerRadius
        iconNode.contentMode = .center
        iconNode.style.preferredSize = CGSize(
            width: PostListCellStyle.Avatar.size,
            height: PostListCellStyle.Avatar.size
        )
        titleNode.maximumNumberOfLines = 2
        titleNode.attributedText = UserContentText.title(record.title)
        titleNode.accessibilityLabel = "打开主题：\(record.title)"
        textNode.maximumNumberOfLines = 3
        textNode.attributedText = Self.commentText(record.text)
        textNode.accessibilityLabel = "打开回复 #\(record.floorID)"
        floorNode.maximumNumberOfLines = 1
        floorNode.attributedText = UserContentText.floor(record.floorID)
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
        textStack.spacing = 6
        textStack.children = [titleNode, textNode, floorNode]
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = 12
        contentStack.alignItems = .start
        contentStack.children = [iconNode, textStack]
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 14, left: 14, bottom: 16, right: 12),
            child: contentStack
        )
    }

    private static func commentText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text.trimmingCharacters(in: .whitespacesAndNewlines),
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
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

    static func metadata(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: PostListCellStyle.Typography.metadataFont,
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
    }

    static func floor(_ floorID: Int) -> NSAttributedString {
        NSAttributedString(
            string: "回复内容  ·  #\(floorID) 楼",
            attributes: [
                .font: PostListCellStyle.Typography.metadataFont,
                .foregroundColor: UIColor.systemOrange
            ]
        )
    }
}
