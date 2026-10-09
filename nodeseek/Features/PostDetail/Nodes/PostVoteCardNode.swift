//
//  PostVoteCardNode.swift
//  nodeseek
//

import AsyncDisplayKit
import UIKit

final class PostVoteCardNode: ASDisplayNode, ThemeRefreshableNode {
    private enum Layout {
        static let contentInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        static let spacing: CGFloat = 10
        static let optionSpacing: CGFloat = 8
        static let cornerRadius: CGFloat = 8
        static let submitHeight: CGFloat = 36
    }

    private let vote: PostVote
    private let onSubmit: ([String]) -> Void
    private let titleNode = ASTextNode()
    private let questionNode = ASTextNode()
    private let statusNode = ASTextNode()
    private let submitButton = ASButtonNode()
    private let themeTraitObserver = ThemeTraitObserver()
    private var selectedOptionIDs: Set<String>
    private var isSubmitting: Bool
    private lazy var optionNodes: [PostVoteOptionNode] = vote.options.map { option in
        PostVoteOptionNode(
            option: option,
            totalVoteCount: vote.totalVoteCount,
            supportsMultipleSelection: vote.allowsMultipleSelection,
            isEnabled: vote.canSubmit && vote.isClosed == false,
            onTap: { [weak self] id in
                self?.toggleSelection(id)
            }
        )
    }

    init(vote: PostVote, onSubmit: @escaping ([String]) -> Void) {
        self.vote = vote
        self.onSubmit = onSubmit
        selectedOptionIDs = Set(vote.options.filter(\.isSelected).map(\.id))
        isSubmitting = vote.isSubmitting
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .secondarySystemBackground
        cornerRadius = Layout.cornerRadius
        accessibilityIdentifier = "post-vote-card"
        configureText()
        configureSubmitButton()
    }

    override func didLoad() {
        super.didLoad()
        themeTraitObserver.install(on: self)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let optionsStack = ASStackLayoutSpec.vertical()
        optionsStack.spacing = Layout.optionSpacing
        optionsStack.children = optionNodes

        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = Layout.spacing
        var children: [ASLayoutElement] = [titleNode, questionNode]
        if statusNode.attributedText != nil {
            children.append(statusNode)
        }
        children.append(optionsStack)
        if shouldShowSubmitButton {
            children.append(submitButton)
        }
        stack.children = children
        return ASInsetLayoutSpec(insets: Layout.contentInset, child: stack)
    }

    func applyCurrentTheme() {
        backgroundColor = .secondarySystemBackground
        configureText()
        refreshOptionNodes()
        refreshSubmitButton()
    }

    private var shouldShowSubmitButton: Bool {
        vote.canSubmit && vote.isClosed == false
    }

    private func configureText() {
        titleNode.attributedText = NSAttributedString(
            string: "投票",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: UIColor.label
            ]
        )
        questionNode.maximumNumberOfLines = 0
        questionNode.attributedText = NSAttributedString(
            string: vote.title,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]
        )

        let status = statusText
        statusNode.attributedText = status.map {
            NSAttributedString(
                string: $0,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .footnote),
                    .foregroundColor: UIColor.secondaryLabel
                ]
            )
        }
    }

    private var statusText: String? {
        var values: [String] = []
        if vote.allowsMultipleSelection {
            values.append("可多选")
        }
        if let total = vote.totalVoteCount {
            values.append("共 \(total) 票")
        }
        if let status = vote.statusText, status.isEmpty == false {
            values.append(status)
        } else if vote.isClosed {
            values.append("投票已结束")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func configureSubmitButton() {
        submitButton.style.height = ASDimension(unit: .points, value: Layout.submitHeight)
        submitButton.cornerRadius = 6
        submitButton.accessibilityIdentifier = "post-vote-submit-button"
        submitButton.addTarget(self, action: #selector(submitTapped), forControlEvents: .touchUpInside)
        refreshSubmitButton()
    }

    private func refreshSubmitButton() {
        let canSubmit = selectedOptionIDs.isEmpty == false && isSubmitting == false
        submitButton.isUserInteractionEnabled = canSubmit
        submitButton.alpha = canSubmit ? 1 : 0.55
        submitButton.backgroundColor = .systemGreen
        submitButton.setAttributedTitle(
            NSAttributedString(
                string: isSubmitting ? "正在提交..." : "提交投票",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.white
                ]
            ),
            for: .normal
        )
    }

    private func toggleSelection(_ optionID: String) {
        guard isSubmitting == false, vote.canSubmit, vote.isClosed == false else { return }
        if vote.allowsMultipleSelection {
            if selectedOptionIDs.contains(optionID) {
                selectedOptionIDs.remove(optionID)
            } else {
                selectedOptionIDs.insert(optionID)
            }
        } else {
            selectedOptionIDs = [optionID]
        }
        refreshOptionNodes()
        refreshSubmitButton()
        setNeedsLayout()
    }

    private func refreshOptionNodes() {
        for optionNode in optionNodes {
            optionNode.applySelection(selectedOptionIDs.contains(optionNode.optionID), isEnabled: isSubmitting == false && vote.canSubmit && vote.isClosed == false)
        }
    }

    @objc private func submitTapped() {
        guard selectedOptionIDs.isEmpty == false, isSubmitting == false else { return }
        isSubmitting = true
        refreshOptionNodes()
        refreshSubmitButton()
        onSubmit(vote.options.filter { selectedOptionIDs.contains($0.id) }.map(\.id))
    }
}

private final class PostVoteOptionNode: ASControlNode {
    private enum Layout {
        static let inset = UIEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        static let spacing: CGFloat = 8
        static let cornerRadius: CGFloat = 6
    }

    let optionID: String
    private let option: PostVoteOption
    private let totalVoteCount: Int?
    private let supportsMultipleSelection: Bool
    private let onTap: (String) -> Void
    private let markerNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let countNode = ASTextNode()
    private var isSelectedOption: Bool
    private var isOptionEnabled: Bool

    init(
        option: PostVoteOption,
        totalVoteCount: Int?,
        supportsMultipleSelection: Bool,
        isEnabled: Bool,
        onTap: @escaping (String) -> Void
    ) {
        optionID = option.id
        self.option = option
        self.totalVoteCount = totalVoteCount
        self.supportsMultipleSelection = supportsMultipleSelection
        isSelectedOption = option.isSelected
        isOptionEnabled = isEnabled
        self.onTap = onTap
        super.init()
        automaticallyManagesSubnodes = true
        cornerRadius = Layout.cornerRadius
        addTarget(self, action: #selector(tapped), forControlEvents: .touchUpInside)
        configureAppearance()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        markerNode.style.preferredSize = CGSize(width: 18, height: 18)
        titleNode.style.flexGrow = 1
        titleNode.style.flexShrink = 1
        let stack = ASStackLayoutSpec.horizontal()
        stack.spacing = Layout.spacing
        stack.alignItems = .center
        stack.children = [markerNode, titleNode, countNode]
        return ASInsetLayoutSpec(insets: Layout.inset, child: stack)
    }

    func applySelection(_ isSelected: Bool, isEnabled: Bool) {
        isSelectedOption = isSelected
        isOptionEnabled = isEnabled
        configureAppearance()
        setNeedsLayout()
    }

    private func configureAppearance() {
        let markerName: String
        if supportsMultipleSelection {
            markerName = isSelectedOption ? "checkmark.square.fill" : "square"
        } else {
            markerName = isSelectedOption ? "largecircle.fill.circle" : "circle"
        }
        markerNode.image = UIImage(systemName: markerName)?.withTintColor(
            isSelectedOption ? .systemGreen : .tertiaryLabel,
            renderingMode: .alwaysOriginal
        )
        markerNode.contentMode = .scaleAspectFit
        backgroundColor = isSelectedOption ? UIColor.systemGreen.withAlphaComponent(0.12) : .systemBackground
        alpha = isOptionEnabled ? 1 : 0.72

        titleNode.maximumNumberOfLines = 0
        titleNode.attributedText = NSAttributedString(
            string: option.title,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.label
            ]
        )
        countNode.attributedText = option.voteCount.map { count in
            let percentage = totalVoteCount.map { total in
                total > 0 ? Int((Double(count) / Double(total) * 100).rounded()) : nil
            } ?? nil
            let text = percentage.map { "\(count) 票 · \($0)%" } ?? "\(count) 票"
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .footnote),
                    .foregroundColor: UIColor.secondaryLabel
                ]
            )
        }
    }

    @objc private func tapped() {
        guard isOptionEnabled else { return }
        onTap(optionID)
    }
}
