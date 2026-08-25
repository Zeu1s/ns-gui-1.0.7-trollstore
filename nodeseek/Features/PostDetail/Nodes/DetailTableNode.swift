//
//  DetailTableNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/29.
//

import AsyncDisplayKit
import UIKit

final class DetailTableNode: ASDisplayNode {
    private let table: RenderedTableBlock

    init(
        table: RenderedTableBlock,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void = { _ in }
    ) {
        self.table = table
        super.init()
        setViewBlock {
            DetailTableScrollView(
                table: table,
                onImageTapped: onImageTapped,
                onLinkTapped: onLinkTapped
            )
        }
        style.flexGrow = 1
        style.flexShrink = 1
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        DetailTableLayout.measure(table: table, constrainedSize: constrainedSize)
    }

    func debugTapFirstLink() {
        (view as? DetailTableScrollView)?.debugTapFirstLink()
    }
}

enum DetailContentBlockNodeFactory {
    static func makeNodes(
        from blocks: [RenderedContentBlock],
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void,
        onSignatureLinkCandidatesTapped: @escaping ([DetailLinkCandidate]) -> Void = { _ in },
        onTextLayoutInvalidated: @escaping () -> Void,
        imageSizeProvider: @escaping (URL) -> CGSize? = { _ in nil },
        onImageSizeResolved: @escaping (URL, CGSize) -> Void = { _, _ in },
        onImageHeightReduced: @escaping () -> Void = {},
        forceReportImages: Bool = false,
        magicTabSelectionKeyPrefix: String? = nil,
        selectedMagicTabIndex: @escaping (String) -> Int? = { _ in nil },
        onMagicTabSelected: @escaping (String, Int) -> Void = { _, _ in }
    ) -> [ASDisplayNode] {
        let imageURLs = imageURLs(in: blocks)
        var imageIndex = 0
        return makeNodes(
            from: blocks,
            imageURLs: imageURLs,
            imageIndex: &imageIndex,
            onImageTapped: onImageTapped,
            onLinkTapped: onLinkTapped,
            onSignatureLinkCandidatesTapped: onSignatureLinkCandidatesTapped,
            onTextLayoutInvalidated: onTextLayoutInvalidated,
            imageSizeProvider: imageSizeProvider,
            onImageSizeResolved: onImageSizeResolved,
            onImageHeightReduced: onImageHeightReduced,
            forceReportImages: forceReportImages,
            magicTabSelectionKeyPrefix: magicTabSelectionKeyPrefix,
            selectedMagicTabIndex: selectedMagicTabIndex,
            onMagicTabSelected: onMagicTabSelected
        )
    }

    private static func makeNodes(
        from blocks: [RenderedContentBlock],
        imageURLs: [URL],
        imageIndex: inout Int,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void,
        onSignatureLinkCandidatesTapped: @escaping ([DetailLinkCandidate]) -> Void,
        onTextLayoutInvalidated: @escaping () -> Void,
        imageSizeProvider: @escaping (URL) -> CGSize?,
        onImageSizeResolved: @escaping (URL, CGSize) -> Void,
        onImageHeightReduced: @escaping () -> Void,
        forceReportImages: Bool = false,
        magicTabSelectionKeyPrefix: String? = nil,
        selectedMagicTabIndex: @escaping (String) -> Int? = { _ in nil },
        onMagicTabSelected: @escaping (String, Int) -> Void = { _, _ in }
    ) -> [ASDisplayNode] {
        return blocks.compactMap { block -> ASDisplayNode? in
            switch block {
            case .text(let attributedText):
                guard attributedText.length > 0 else { return nil }
                return DetailRichTextNode(
                    attributedText: attributedText,
                    imageSizeProvider: imageSizeProvider,
                    onImageSizeResolved: onImageSizeResolved,
                    onImageTapped: onImageTapped,
                    onLinkTapped: onLinkTapped,
                    onSignatureLinkCandidatesTapped: onSignatureLinkCandidatesTapped,
                    onLayoutInvalidated: onTextLayoutInvalidated
                )
            case .table(let table):
                guard table.rows.isEmpty == false else { return nil }
                return DetailTableNode(
                    table: table,
                    onImageTapped: onImageTapped,
                    onLinkTapped: onLinkTapped
                )
            case .codeBlock(let codeBlock):
                guard codeBlock.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    return nil
                }
                return DetailCodeBlockNode(codeBlock: codeBlock)
            case .image(let imageBlock):
                let index = imageIndex
                imageIndex += 1
                return DetailImageBlockNode(
                    imageBlock: imageBlock,
                    imageURLs: imageURLs,
                    imageIndex: index,
                    initialImageSize: imageSizeProvider(imageBlock.url) ?? .zero,
                    resolvedKind: forceReportImages ? .report : nil,
                    animateAppearance: forceReportImages,
                    onImageTapped: onImageTapped,
                    onImageSizeResolved: onImageSizeResolved,
                    onImageHeightReduced: onImageHeightReduced,
                    onLayoutInvalidated: onTextLayoutInvalidated
                )
            case .magicTabs(let magicTabs):
                var tabs: [DetailMagicTabsNode.Tab] = []
                for tab in magicTabs.tabs {
                    let bodyNodes = makeNodes(
                        from: tab.blocks,
                        imageURLs: imageURLs,
                        imageIndex: &imageIndex,
                        onImageTapped: onImageTapped,
                        onLinkTapped: onLinkTapped,
                        onSignatureLinkCandidatesTapped: onSignatureLinkCandidatesTapped,
                        onTextLayoutInvalidated: onTextLayoutInvalidated,
                        imageSizeProvider: imageSizeProvider,
                        onImageSizeResolved: onImageSizeResolved,
                        onImageHeightReduced: onImageHeightReduced,
                        forceReportImages: true,
                        magicTabSelectionKeyPrefix: magicTabSelectionKeyPrefix,
                        selectedMagicTabIndex: selectedMagicTabIndex,
                        onMagicTabSelected: onMagicTabSelected
                    )
                    if bodyNodes.isEmpty == false {
                        tabs.append(DetailMagicTabsNode.Tab(title: tab.title, bodyNodes: bodyNodes))
                    }
                }
                guard tabs.isEmpty == false else { return nil }
                let tabKey = magicTabSelectionKeyPrefix.map {
                    "\($0):\(tabs.map(\.title).joined(separator: "|"))"
                }
                return DetailMagicTabsNode(
                    tabs: tabs,
                    initialSelectedIndex: tabKey.flatMap(selectedMagicTabIndex) ?? 0,
                    onSelectionChanged: { index in
                        if let tabKey {
                            onMagicTabSelected(tabKey, index)
                        }
                    },
                    onLayoutInvalidated: onTextLayoutInvalidated
                )
            case .iframeLink(let iframeBlock):
                return DetailIFrameLinkNode(
                    iframeBlock: iframeBlock,
                    onLinkTapped: onLinkTapped
                )
            case .imagePlaceholder(let url):
                return plainTextNode(url?.absoluteString ?? "[图片]")
            case .unsupported(let reason):
                return plainTextNode(reason)
            case .quote(let quoteBlock):
                let childNodes = makeNodes(
                    from: quoteBlock.children,
                    imageURLs: imageURLs,
                    imageIndex: &imageIndex,
                    onImageTapped: onImageTapped,
                    onLinkTapped: onLinkTapped,
                    onSignatureLinkCandidatesTapped: onSignatureLinkCandidatesTapped,
                    onTextLayoutInvalidated: onTextLayoutInvalidated,
                    imageSizeProvider: imageSizeProvider,
                    onImageSizeResolved: onImageSizeResolved,
                    onImageHeightReduced: onImageHeightReduced,
                    forceReportImages: forceReportImages,
                    magicTabSelectionKeyPrefix: magicTabSelectionKeyPrefix,
                    selectedMagicTabIndex: selectedMagicTabIndex,
                    onMagicTabSelected: onMagicTabSelected
                )
                guard childNodes.isEmpty == false else { return nil }
                return DetailQuoteBlockNode(children: childNodes)
            }
        }
    }

    private static func imageURLs(in blocks: [RenderedContentBlock]) -> [URL] {
        blocks.flatMap { block -> [URL] in
            switch block {
            case .image(let imageBlock):
                return [imageBlock.url]
            case .quote(let quoteBlock):
                return imageURLs(in: quoteBlock.children)
            case .magicTabs(let magicTabs):
                return magicTabs.tabs.flatMap { imageURLs(in: $0.blocks) }
            case .text, .table, .codeBlock, .iframeLink, .imagePlaceholder, .unsupported:
                return []
            }
        }
    }

    private static func plainTextNode(_ text: String) -> ASTextNode? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else { return nil }

        let node = ASTextNode()
        node.maximumNumberOfLines = 0
        node.attributedText = NSAttributedString(
            string: trimmedText,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
        return node
    }
}

final class DetailQuoteBlockNode: ASDisplayNode, ThemeRefreshableNode {
    private enum Layout {
        static let borderWidth: CGFloat = 3
        static let cornerRadius: CGFloat = 4
        static let contentSpacing: CGFloat = 8
        static let blockSpacing: CGFloat = 8
        static let insets = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 10)
    }

    private let children: [ASDisplayNode]
    private let borderNode = ASDisplayNode()

    var debugBorderNode: ASDisplayNode {
        borderNode
    }

    init(children: [ASDisplayNode]) {
        self.children = children
        super.init()
        automaticallyManagesSubnodes = true
        style.flexGrow = 1
        style.flexShrink = 1
        applyCurrentTheme()
    }

    override func didLoad() {
        super.didLoad()
        themeTraitObserver.install(on: self)
        view.layer.cornerRadius = Layout.cornerRadius
        view.layer.masksToBounds = true
    }

    private let themeTraitObserver = ThemeTraitObserver()

    func applyCurrentTheme() {
        backgroundColor = .secondarySystemBackground
        borderNode.backgroundColor = .separator
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        borderNode.style.width = ASDimension(unit: .points, value: Layout.borderWidth)
        borderNode.style.flexShrink = 0
        borderNode.style.alignSelf = .stretch

        let contentStack = ASStackLayoutSpec.vertical()
        contentStack.spacing = Layout.blockSpacing
        contentStack.children = children
        contentStack.style.flexGrow = 1
        contentStack.style.flexShrink = 1
        let contentInsets = UIEdgeInsets(
            top: Layout.insets.top,
            left: Layout.contentSpacing,
            bottom: Layout.insets.bottom,
            right: Layout.insets.right
        )
        let paddedContent = ASInsetLayoutSpec(insets: contentInsets, child: contentStack)
        paddedContent.style.flexGrow = 1
        paddedContent.style.flexShrink = 1

        let horizontalStack = ASStackLayoutSpec.horizontal()
        horizontalStack.alignItems = .stretch
        horizontalStack.children = [borderNode, paddedContent]

        return horizontalStack
    }
}

final class DetailIFrameLinkNode: ASDisplayNode {
    private let iframeBlock: RenderedIFrameLinkBlock

    init(
        iframeBlock: RenderedIFrameLinkBlock,
        onLinkTapped: @escaping (URL) -> Void
    ) {
        self.iframeBlock = iframeBlock
        super.init()
        setViewBlock {
            DetailIFrameLinkView(
                iframeBlock: iframeBlock,
                onTapped: {
                    onLinkTapped(iframeBlock.openURL)
                }
            )
        }
        style.flexGrow = 1
        style.flexShrink = 1
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        DetailIFrameLinkLayout.measure(
            iframeBlock: iframeBlock,
            constrainedSize: constrainedSize
        )
    }
}

private final class DetailIFrameLinkView: UIControl {
    private let iframeBlock: RenderedIFrameLinkBlock
    private let onTapped: () -> Void
    private let titleLabel = UILabel()
    private let sourceLabel = UILabel()

    init(
        iframeBlock: RenderedIFrameLinkBlock,
        onTapped: @escaping () -> Void
    ) {
        self.iframeBlock = iframeBlock
        self.onTapped = onTapped
        super.init(frame: .zero)
        configureView()
        configureLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.72 : 1
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = DetailIFrameLinkLayout.frames(
            iframeBlock: iframeBlock,
            bounds: bounds
        )
        titleLabel.frame = frames.title
        sourceLabel.frame = frames.source
    }

    private func configureView() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.masksToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = [.button, .link]
        accessibilityLabel = "嵌入内容 \(iframeBlock.displayDomain) \(iframeBlock.source)"
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    private func configureLabels() {
        titleLabel.font = DetailIFrameLinkLayout.titleFont
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.text = DetailIFrameLinkLayout.titleText(displayDomain: iframeBlock.displayDomain)
        addSubview(titleLabel)

        sourceLabel.font = DetailIFrameLinkLayout.sourceFont
        sourceLabel.textColor = .secondaryLabel
        sourceLabel.numberOfLines = 2
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.text = iframeBlock.source
        addSubview(sourceLabel)
    }

    @objc
    private func handleTap() {
        onTapped()
    }
}

enum DetailIFrameLinkLayout {
    static let titleFont = UIFont.preferredFont(forTextStyle: .subheadline)
    static let sourceFont = UIFont.preferredFont(forTextStyle: .footnote)
    private static let fallbackWidth: CGFloat = 320
    private static let horizontalInset: CGFloat = 14
    private static let verticalInset: CGFloat = 12
    private static let labelSpacing: CGFloat = 4

    static func measure(
        iframeBlock: RenderedIFrameLinkBlock,
        constrainedSize: CGSize
    ) -> CGSize {
        let width = resolvedWidth(constrainedSize.width)
        let textWidth = max(width - horizontalInset * 2, 1)
        let titleHeight = ceil(titleText(displayDomain: iframeBlock.displayDomain).height(
            font: titleFont,
            width: textWidth,
            maximumNumberOfLines: 1
        ))
        let sourceHeight = ceil(iframeBlock.source.height(
            font: sourceFont,
            width: textWidth,
            maximumNumberOfLines: 2
        ))
        return CGSize(
            width: width,
            height: verticalInset * 2 + titleHeight + labelSpacing + sourceHeight
        )
    }

    static func frames(
        iframeBlock: RenderedIFrameLinkBlock,
        bounds: CGRect
    ) -> (title: CGRect, source: CGRect) {
        let textWidth = max(bounds.width - horizontalInset * 2, 1)
        let titleHeight = ceil(titleText(displayDomain: iframeBlock.displayDomain).height(
            font: titleFont,
            width: textWidth,
            maximumNumberOfLines: 1
        ))
        let sourceHeight = ceil(iframeBlock.source.height(
            font: sourceFont,
            width: textWidth,
            maximumNumberOfLines: 2
        ))
        let titleFrame = CGRect(
            x: horizontalInset,
            y: verticalInset,
            width: textWidth,
            height: titleHeight
        )
        let sourceFrame = CGRect(
            x: horizontalInset,
            y: titleFrame.maxY + labelSpacing,
            width: textWidth,
            height: sourceHeight
        )
        return (titleFrame, sourceFrame)
    }

    static func titleText(displayDomain: String) -> String {
        "嵌入内容 · \(displayDomain) · 点击查看"
    }

    private static func resolvedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return fallbackWidth }
        return width
    }
}

private extension String {
    func height(font: UIFont, width: CGFloat, maximumNumberOfLines: Int) -> CGFloat {
        let lineHeight = font.lineHeight * CGFloat(max(maximumNumberOfLines, 1))
        let measured = (self as NSString).boundingRect(
            with: CGSize(width: width, height: lineHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return min(ceil(measured.height), lineHeight)
    }
}

final class DetailCodeBlockNode: ASDisplayNode {
    private let codeBlock: RenderedCodeBlock

    init(
        codeBlock: RenderedCodeBlock,
        pasteboardStringWriter: @escaping PasteboardStringWriter = { UIPasteboard.general.string = $0 }
    ) {
        self.codeBlock = codeBlock
        super.init()
        setViewBlock { [pasteboardStringWriter] in
            DetailCodeBlockView(
                codeBlock: codeBlock,
                pasteboardStringWriter: pasteboardStringWriter
            )
        }
        style.flexGrow = 1
        style.flexShrink = 1
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        DetailCodeBlockLayout.measure(codeBlock: codeBlock, constrainedSize: constrainedSize)
    }
}

final class DetailCodeBlockView: UIView {
    private let codeBlock: RenderedCodeBlock
    private let pasteboardStringWriter: PasteboardStringWriter
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let codeLabel = UILabel()
    private let terminalCanvasView: TerminalReportCanvasView?
    private let chromeDotsStack = UIStackView()
    private let copyButton = UIButton(type: .system)
    private var contentWidthConstraint: NSLayoutConstraint?
    private var copyResetWorkItem: DispatchWorkItem?

    private var showsChrome: Bool {
        codeBlock.style == .standard
    }

    init(
        codeBlock: RenderedCodeBlock,
        pasteboardStringWriter: @escaping PasteboardStringWriter = { UIPasteboard.general.string = $0 }
    ) {
        self.codeBlock = codeBlock
        self.pasteboardStringWriter = pasteboardStringWriter
        self.terminalCanvasView = codeBlock.style == .terminal
            ? TerminalReportCanvasView(codeBlock: codeBlock)
            : nil
        super.init(frame: .zero)
        configureView()
        if showsChrome {
            configureChromeDots()
            configureCopyButton()
        }
        configureScrollView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        copyResetWorkItem?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let nextWidth = DetailCodeBlockLayout.contentWidth(
            for: codeBlock,
            viewportWidth: bounds.width
        )
        guard let contentWidthConstraint,
              abs(contentWidthConstraint.constant - nextWidth) > 0.5 else {
            return
        }
        contentWidthConstraint.constant = nextWidth
    }

    private func configureView() {
        backgroundColor = showsChrome
            ? .secondarySystemBackground
            : UIColor(red: 29 / 255, green: 29 / 255, blue: 29 / 255, alpha: 1)
        layer.cornerRadius = 8
        layer.masksToBounds = true
    }

    private func configureChromeDots() {
        chromeDotsStack.axis = .horizontal
        chromeDotsStack.alignment = .center
        chromeDotsStack.spacing = 7
        chromeDotsStack.isUserInteractionEnabled = false
        chromeDotsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chromeDotsStack)

        [
            UIColor(red: 1, green: 95 / 255, blue: 101 / 255, alpha: 1),
            UIColor(red: 1, green: 204 / 255, blue: 41 / 255, alpha: 1),
            UIColor(red: 46 / 255, green: 204 / 255, blue: 84 / 255, alpha: 1)
        ].forEach { color in
            let dot = UIView()
            dot.backgroundColor = color
            dot.layer.cornerRadius = DetailCodeBlockLayout.chromeDotSize / 2
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: DetailCodeBlockLayout.chromeDotSize),
                dot.heightAnchor.constraint(equalToConstant: DetailCodeBlockLayout.chromeDotSize)
            ])
            chromeDotsStack.addArrangedSubview(dot)
        }

        NSLayoutConstraint.activate([
            chromeDotsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            chromeDotsStack.centerYAnchor.constraint(equalTo: topAnchor, constant: DetailCodeBlockLayout.chromeHeight / 2)
        ])
    }

    private func configureCopyButton() {
        copyButton.accessibilityIdentifier = "detail-code-copy-button"
        copyButton.accessibilityLabel = "复制代码"
        copyButton.tintColor = .secondaryLabel
        copyButton.setImage(copyIcon(named: "doc.on.doc"), for: .normal)
        copyButton.addTarget(self, action: #selector(copyCode), for: .touchUpInside)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(copyButton)

        NSLayoutConstraint.activate([
            copyButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            copyButton.widthAnchor.constraint(equalToConstant: 30),
            copyButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func configureScrollView() {
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentView.backgroundColor = .clear
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        let contentNode: UIView
        if let terminalCanvasView {
            terminalCanvasView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(terminalCanvasView)
            contentNode = terminalCanvasView
        } else {
            codeLabel.numberOfLines = 0
            codeLabel.lineBreakMode = .byClipping
            codeLabel.font = DetailCodeBlockLayout.codeFont
            codeLabel.textColor = .label
            codeLabel.attributedText = attributedCodeText()
            codeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            codeLabel.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(codeLabel)
            contentNode = codeLabel
        }

        let widthConstraint = contentView.widthAnchor.constraint(
            equalToConstant: DetailCodeBlockLayout.contentWidth(
                for: codeBlock,
                viewportWidth: DetailCodeBlockLayout.fallbackViewportWidth
            )
        )
        contentWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: DetailCodeBlockLayout.contentTopInset(for: codeBlock.style)
            ),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DetailCodeBlockLayout.bottomInset),

            widthConstraint,
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            contentNode.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DetailCodeBlockLayout.horizontalInset),
            contentNode.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DetailCodeBlockLayout.horizontalInset),
            contentNode.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentNode.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])

        if let terminalCanvasView {
            NSLayoutConstraint.activate([
                terminalCanvasView.heightAnchor.constraint(
                    equalToConstant: DetailCodeBlockLayout.terminalTextHeight(for: codeBlock.text)
                ),
                terminalCanvasView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    private func attributedCodeText() -> NSAttributedString {
        guard codeBlock.style == .terminal else {
            return NSAttributedString(
                string: codeBlock.text,
                attributes: [
                    .font: DetailCodeBlockLayout.codeFont,
                    .foregroundColor: UIColor.label
                ]
            )
        }

        let text = NSMutableAttributedString(
            string: codeBlock.text,
            attributes: [
                .font: DetailCodeBlockLayout.codeFont,
                .foregroundColor: UIColor.white
            ]
        )
        let textLength = text.length
        for run in codeBlock.runs {
            let range = NSRange(location: max(0, run.location), length: max(0, run.length))
            guard NSMaxRange(range) <= textLength, range.length > 0 else { continue }
            if let foreground = run.foregroundColorIndex {
                text.addAttribute(.foregroundColor, value: TerminalPalette.color(index: foreground), range: range)
            }
            if let background = run.backgroundColorIndex {
                text.addAttribute(.backgroundColor, value: TerminalPalette.color(index: background), range: range)
            }
            if run.isBold || run.isItalic {
                text.addAttribute(
                    .font,
                    value: TerminalPalette.font(isBold: run.isBold, isItalic: run.isItalic),
                    range: range
                )
            }
            if run.isUnderlined {
                text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        return text
    }

    @objc
    private func copyCode() {
        pasteboardStringWriter(codeBlock.text)
        showCopiedState()
    }

    private func showCopiedState() {
        copyResetWorkItem?.cancel()
        copyButton.setImage(copyIcon(named: "checkmark"), for: .normal)

        let workItem = DispatchWorkItem { [weak self] in
            self?.copyButton.setImage(self?.copyIcon(named: "doc.on.doc"), for: .normal)
        }
        copyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: workItem)
    }

    private func copyIcon(named name: String) -> UIImage? {
        UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
    }
}

/// 按终端字符网格绘制 ANSI 报告。不能把 ANSI 背景交给 UILabel：中文回退字形的
/// 宽度并不等于终端列宽，会让 NodeQuality 的色块与文字错列。
final class TerminalReportCanvasView: UIView {
    private let codeBlock: RenderedCodeBlock
    private let lines: [Substring]

    init(codeBlock: RenderedCodeBlock) {
        self.codeBlock = codeBlock
        self.lines = codeBlock.text.split(separator: "\n", omittingEmptySubsequences: false)
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        UIColor(red: 29 / 255, green: 29 / 255, blue: 29 / 255, alpha: 1).setFill()
        UIRectFill(bounds)

        var utf16Location = 0
        for (lineIndex, line) in lines.enumerated() {
            let lineOrigin = CGFloat(lineIndex) * DetailCodeBlockLayout.terminalLineHeight
            var column = 0

            for character in line {
                let characterText = String(character)
                let characterLength = (characterText as NSString).length
                let style = terminalStyle(at: utf16Location)
                let columnCount = DetailCodeBlockLayout.terminalColumnCount(for: character)
                let width = CGFloat(columnCount) * DetailCodeBlockLayout.terminalCellWidth
                let frame = CGRect(
                    x: CGFloat(column) * DetailCodeBlockLayout.terminalCellWidth,
                    y: lineOrigin,
                    width: width,
                    height: DetailCodeBlockLayout.terminalLineHeight
                )

                if let background = style?.backgroundColorIndex {
                    TerminalPalette.color(index: background).setFill()
                    UIRectFill(frame)
                }

                let isBold = style?.isBold ?? false
                let isItalic = style?.isItalic ?? false
                let foreground = style?.foregroundColorIndex.map { TerminalPalette.color(index: $0) }
                    ?? UIColor.white
                (characterText as NSString).draw(
                    at: CGPoint(x: frame.minX, y: frame.minY),
                    withAttributes: [
                        .font: TerminalPalette.font(isBold: isBold, isItalic: isItalic),
                        .foregroundColor: foreground
                    ]
                )

                column += columnCount
                utf16Location += characterLength
            }

            if lineIndex < lines.count - 1 {
                utf16Location += 1
            }
        }
    }

    private func terminalStyle(at location: Int) -> RenderedCodeBlockRun? {
        codeBlock.runs.first { run in
            location >= run.location && location < run.location + run.length
        }
    }
}

enum DetailCodeBlockLayout {
    static let codeFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let chromeHeight: CGFloat = 38
    static let maximumContentWidth: CGFloat = 4096
    static let bottomInset: CGFloat = 12
    static let horizontalInset: CGFloat = 12
    static let chromeDotSize: CGFloat = 10
    static let fallbackViewportWidth: CGFloat = 320

    private enum Layout {
        static let minHeight: CGFloat = 64
    }

    static func measure(codeBlock: RenderedCodeBlock, constrainedSize: CGSize) -> CGSize {
        let width = resolvedWidth(constrainedSize.width)
        let lineCount = max(codeBlock.text.components(separatedBy: .newlines).count, 1)
        let textHeight = codeBlock.style == .terminal
            ? terminalTextHeight(for: codeBlock.text)
            : CGFloat(lineCount) * max(codeFont.lineHeight, 1)
        let height = max(
            Layout.minHeight,
            contentTopInset(for: codeBlock.style) + textHeight + bottomInset
        )
        return CGSize(width: width, height: ceil(height))
    }

    static func contentTopInset(for style: RenderedCodeBlockStyle) -> CGFloat {
        style == .terminal ? 10 : chromeHeight
    }

    static func naturalCodeWidth(for text: String) -> CGFloat {
        let lines = text.components(separatedBy: .newlines)
        let maxLineWidth = lines.reduce(CGFloat(0)) { partialResult, line in
            let width = (line as NSString).size(withAttributes: [.font: codeFont]).width
            return max(partialResult, ceil(width))
        }
        return max(maxLineWidth + horizontalInset * 2, horizontalInset * 2)
    }

    static func contentWidth(for text: String, viewportWidth: CGFloat) -> CGFloat {
        min(max(naturalCodeWidth(for: text), resolvedWidth(viewportWidth)), maximumContentWidth)
    }

    static func contentWidth(for codeBlock: RenderedCodeBlock, viewportWidth: CGFloat) -> CGFloat {
        guard codeBlock.style == .terminal else {
            return contentWidth(for: codeBlock.text, viewportWidth: viewportWidth)
        }
        return min(
            max(terminalNaturalCodeWidth(for: codeBlock.text), resolvedWidth(viewportWidth)),
            maximumContentWidth
        )
    }

    static let terminalCellWidth = ceil(("0" as NSString).size(withAttributes: [.font: codeFont]).width)
    static let terminalLineHeight = ceil(codeFont.lineHeight)

    static func terminalTextHeight(for text: String) -> CGFloat {
        let lineCount = max(text.components(separatedBy: .newlines).count, 1)
        return CGFloat(lineCount) * terminalLineHeight
    }

    static func terminalNaturalCodeWidth(for text: String) -> CGFloat {
        let widestLine = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.reduce(0) { $0 + terminalColumnCount(for: $1) } }
            .max() ?? 0
        return max(CGFloat(widestLine) * terminalCellWidth + horizontalInset * 2, horizontalInset * 2)
    }

    static func terminalColumnCount(for character: Character) -> Int {
        guard character != "\t" else { return 4 }
        return character.unicodeScalars.contains(where: { scalar in
            switch scalar.value {
            case 0x1100...0x115F,
                 0x2329...0x232A,
                 0x2E80...0xA4CF,
                 0xAC00...0xD7A3,
                 0xF900...0xFAFF,
                 0xFE10...0xFE19,
                 0xFE30...0xFE6F,
                 0xFF00...0xFF60,
                 0xFFE0...0xFFE6,
                 0x1F300...0x1FAFF:
                return true
            default:
                return false
            }
        }) ? 2 : 1
    }

    private static func resolvedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else {
            return fallbackViewportWidth
        }
        return width
    }
}

private enum TerminalPalette {
    static func color(index: Int) -> UIColor {
        let value = max(0, min(index, 255))
        let baseColors: [(CGFloat, CGFloat, CGFloat)] = [
            (46, 52, 54), (204, 0, 0), (78, 154, 6), (196, 160, 0),
            (52, 101, 164), (117, 80, 123), (6, 152, 154), (211, 215, 207),
            (85, 87, 83), (239, 41, 41), (138, 226, 52), (252, 233, 79),
            (114, 159, 207), (173, 127, 168), (52, 226, 226), (238, 238, 236)
        ]
        if value < baseColors.count {
            let color = baseColors[value]
            return UIColor(red: color.0 / 255, green: color.1 / 255, blue: color.2 / 255, alpha: 1)
        }
        if value >= 232 {
            let gray = CGFloat(8 + (value - 232) * 10) / 255
            return UIColor(white: gray, alpha: 1)
        }
        let cubeIndex = value - 16
        let levels: [CGFloat] = [0, 95, 135, 175, 215, 255]
        let red = levels[cubeIndex / 36]
        let green = levels[(cubeIndex % 36) / 6]
        let blue = levels[cubeIndex % 6]
        return UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    static func font(isBold: Bool, isItalic: Bool) -> UIFont {
        let base = UIFont.monospacedSystemFont(
            ofSize: DetailCodeBlockLayout.codeFont.pointSize,
            weight: isBold ? .bold : .regular
        )
        guard isItalic,
              let descriptor = base.fontDescriptor.withSymbolicTraits(
                base.fontDescriptor.symbolicTraits.union(.traitItalic)
              ) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}

private final class DetailTableScrollView: UIScrollView {
    private let table: RenderedTableBlock
    private let tableImageURLs: [URL]
    private let onImageTapped: ([URL], Int) -> Void
    private let onLinkTapped: (URL) -> Void
    private let contentContainer = UIView()
    private let contentWidthConstraint: NSLayoutConstraint
    private var cellWidthConstraints: [[NSLayoutConstraint]] = []
    private var rowHeightConstraints: [NSLayoutConstraint] = []

    init(
        table: RenderedTableBlock,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void
    ) {
        self.table = table
        self.tableImageURLs = table.imageURLs
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
        self.contentWidthConstraint = contentContainer.widthAnchor.constraint(equalToConstant: 0)
        super.init(frame: .zero)
        configureScrollView()
        buildTable()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyTableLayout(for: bounds.width)
    }

    private func configureScrollView() {
        backgroundColor = .clear
        showsHorizontalScrollIndicator = true
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true
        alwaysBounceVertical = false
        bounces = true
        contentInsetAdjustmentBehavior = .never
        isDirectionalLockEnabled = true

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            contentContainer.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
            contentWidthConstraint
        ])
    }

    private func buildTable() {
        let columnWidths = DetailTableLayout.columnWidths(for: table)
        let rowHeights = DetailTableLayout.rowHeights(for: table, columnWidths: columnWidths)
        contentWidthConstraint.constant = columnWidths.reduce(0, +)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        for (rowIndex, row) in table.rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 0
            rowStack.alignment = .fill
            rowStack.distribution = .fill
            let rowHeightConstraint = rowStack.heightAnchor.constraint(
                equalToConstant: rowHeights[safe: rowIndex] ?? DetailTableLayout.defaultRowHeight
            )
            rowHeightConstraint.isActive = true
            rowHeightConstraints.append(rowHeightConstraint)

            var widthConstraints: [NSLayoutConstraint] = []
            for columnIndex in columnWidths.indices {
                let cell = row.cells[safe: columnIndex]
                let cellView = DetailTableCellView(
                    cell: cell,
                    columnWidth: columnWidths[columnIndex],
                    isHeader: row.isHeader || (cell?.isHeader == true),
                    tableImageURLs: tableImageURLs,
                    onImageTapped: onImageTapped,
                    onLinkTapped: onLinkTapped
                )
                let widthConstraint = cellView.widthAnchor.constraint(equalToConstant: columnWidths[columnIndex])
                widthConstraint.isActive = true
                widthConstraints.append(widthConstraint)
                rowStack.addArrangedSubview(cellView)
            }
            cellWidthConstraints.append(widthConstraints)
            stack.addArrangedSubview(rowStack)
        }
    }

    private func applyTableLayout(for viewportWidth: CGFloat) {
        let columnWidths = DetailTableLayout.columnWidths(for: table, fittingWidth: viewportWidth)
        let rowHeights = DetailTableLayout.rowHeights(for: table, columnWidths: columnWidths)
        contentWidthConstraint.constant = max(columnWidths.reduce(0, +), viewportWidth)

        for rowIndex in cellWidthConstraints.indices {
            for columnIndex in cellWidthConstraints[rowIndex].indices {
                guard let width = columnWidths[safe: columnIndex] else { continue }
                cellWidthConstraints[rowIndex][columnIndex].constant = width
            }
        }

        for rowIndex in rowHeightConstraints.indices {
            rowHeightConstraints[rowIndex].constant = rowHeights[safe: rowIndex] ?? DetailTableLayout.defaultRowHeight
        }
    }

    func debugTapFirstLink() {
        _ = contentContainer.debugTapFirstTableLink()
    }
}

private final class DetailTableCellView: UIView {
    private enum Layout {
        static let contentInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    }

    private var linkTapHandler: DetailTableLinkTapHandler?

    init(
        cell: RenderedTableBlock.Cell?,
        columnWidth: CGFloat,
        isHeader: Bool,
        tableImageURLs: [URL],
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void
    ) {
        super.init(frame: .zero)
        backgroundColor = isHeader ? .secondarySystemBackground : .systemBackground
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1 / max(traitCollection.displayScale, 2)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        if let imageURL = cell?.imageURL {
            let imageView = DetailTableImageView(
                imageURL: imageURL,
                targetPixelWidth: max(columnWidth - Layout.contentInsets.left - Layout.contentInsets.right, 1),
                onTapped: {
                    guard let index = tableImageURLs.firstIndex(of: imageURL) else { return }
                    onImageTapped(tableImageURLs, index)
                }
            )
            imageView.heightAnchor.constraint(equalToConstant: DetailTableLayout.imageHeight).isActive = true
            stack.addArrangedSubview(imageView)
        }

        if let text = cell?.text, text.isEmpty == false {
            let label = UILabel()
            label.numberOfLines = 0
            label.lineBreakMode = .byCharWrapping
            let font = isHeader
                ? UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
                : UIFont.preferredFont(forTextStyle: .subheadline)
            let textColor = isHeader ? UIColor.label : UIColor.secondaryLabel
            if let links = cell?.links, links.isEmpty == false {
                label.attributedText = Self.attributedText(
                    text,
                    font: font,
                    textColor: textColor,
                    links: links
                )
                label.isUserInteractionEnabled = true
                let handler = DetailTableLinkTapHandler(label: label, links: links, onTapped: onLinkTapped)
                label.addGestureRecognizer(UITapGestureRecognizer(target: handler, action: #selector(DetailTableLinkTapHandler.handleTap(_:))))
                linkTapHandler = handler
            } else {
                label.font = font
                label.textColor = textColor
                label.text = text
            }
            stack.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.contentInsets.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.contentInsets.right),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Layout.contentInsets.top),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Layout.contentInsets.bottom)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func attributedText(
        _ text: String,
        font: UIFont,
        textColor: UIColor,
        links: [RenderedTableBlock.Cell.Link]
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
        for link in links where NSMaxRange(link.nsRange) <= attributed.length {
            attributed.addAttributes(NodeSeekLinkStyle.attributes(url: link.url), range: link.nsRange)
        }
        return attributed
    }
}

extension DetailTableCellView: DetailTableLinkDebugTappable {
    func debugTapFirstLink() -> Bool {
        guard let linkTapHandler else { return false }
        return linkTapHandler.debugTapFirstLink()
    }
}

private protocol DetailTableLinkDebugTappable {
    func debugTapFirstLink() -> Bool
}

private final class DetailTableLinkTapHandler: NSObject {
    private weak var label: UILabel?
    private let links: [RenderedTableBlock.Cell.Link]
    private let onTapped: (URL) -> Void

    init(
        label: UILabel,
        links: [RenderedTableBlock.Cell.Link],
        onTapped: @escaping (URL) -> Void
    ) {
        self.label = label
        self.links = links
        self.onTapped = onTapped
    }

    @objc
    func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let label,
              let link = DetailTableLinkHitTester.link(
                at: recognizer.location(in: label),
                in: label,
                links: links
              ) else {
            return
        }
        onTapped(link.url)
    }

    func debugTapFirstLink() -> Bool {
        guard let link = links.first else { return false }
        onTapped(link.url)
        return true
    }
}

private enum DetailTableLinkHitTester {
    static func link(
        at point: CGPoint,
        in label: UILabel,
        links: [RenderedTableBlock.Cell.Link]
    ) -> RenderedTableBlock.Cell.Link? {
        guard let attributedText = label.attributedText,
              attributedText.length > 0,
              label.bounds.width > 0,
              label.bounds.height > 0 else {
            return nil
        }

        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: label.bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = label.numberOfLines
        textContainer.lineBreakMode = label.lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let horizontalOffset: CGFloat
        switch label.textAlignment {
        case .center:
            horizontalOffset = (label.bounds.width - usedRect.width) * 0.5 - usedRect.minX
        case .right:
            horizontalOffset = label.bounds.width - usedRect.width - usedRect.minX
        default:
            horizontalOffset = -usedRect.minX
        }
        let offset = CGPoint(
            x: horizontalOffset,
            y: (label.bounds.height - usedRect.height) * 0.5 - usedRect.minY
        )
        let textPoint = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
        let index = layoutManager.characterIndex(
            for: textPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        return links.first { NSLocationInRange(index, $0.nsRange) }
    }
}

private final class DetailTableImageView: UIImageView {
    private let imageURL: URL
    private let targetPixelWidth: CGFloat
    private let onTapped: () -> Void
    private var loadToken: UUID?

    init(
        imageURL: URL,
        targetPixelWidth: CGFloat,
        onTapped: @escaping () -> Void
    ) {
        self.imageURL = imageURL
        self.targetPixelWidth = targetPixelWidth
        self.onTapped = onTapped
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        contentMode = .scaleAspectFit
        clipsToBounds = true
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil else {
            loadToken = nil
            image = nil
            return
        }
        guard loadToken == nil else { return }

        let token = UUID()
        loadToken = token
        let displayScale = max(traitCollection.displayScale, 1)
        ImageLoad.url(imageURL)
            .toDetailInline(
                maxPixelWidth: targetPixelWidth * displayScale,
                displayScale: displayScale
            )
            .load { [weak self] image in
                DispatchQueue.main.async {
                    guard let self, self.loadToken == token else { return }
                    self.image = image
                }
            }
    }

    @objc
    private func handleTap() {
        onTapped()
    }
}

enum DetailTableLayout {
    static let defaultRowHeight: CGFloat = 38
    static let imageHeight: CGFloat = 150

    private enum Layout {
        static let fallbackWidth: CGFloat = 320
        static let minColumnWidth: CGFloat = 96
        static let maxColumnWidth: CGFloat = 220
        static let imageColumnWidth: CGFloat = 220
        static let horizontalPadding: CGFloat = 24
        static let verticalPadding: CGFloat = 18
        static let estimatedCharacterWidth: CGFloat = 7.5
        static let estimatedLineHeight: CGFloat = 19
    }

    static func measure(table: RenderedTableBlock, constrainedSize: CGSize) -> CGSize {
        let width = resolvedWidth(constrainedSize.width)
        let columnWidths = columnWidths(for: table, fittingWidth: width)
        let rowHeights = rowHeights(for: table, columnWidths: columnWidths)
        let height = max(rowHeights.reduce(0, +), defaultRowHeight)
        return CGSize(width: width, height: ceil(height))
    }

    static func columnWidths(for table: RenderedTableBlock, fittingWidth width: CGFloat? = nil) -> [CGFloat] {
        let columnCount = table.rows.map(\.cells.count).max() ?? 0
        guard columnCount > 0 else { return [] }

        let naturalWidths = (0..<columnCount).map { columnIndex in
            let maxTextLength = table.rows
                .compactMap { $0.cells[safe: columnIndex]?.text.count }
                .max() ?? 0
            let estimatedWidth = CGFloat(maxTextLength) * Layout.estimatedCharacterWidth + Layout.horizontalPadding
            let containsImage = table.rows.contains { $0.cells[safe: columnIndex]?.imageURL != nil }
            let minimumWidth = containsImage ? Layout.imageColumnWidth : Layout.minColumnWidth
            return min(max(estimatedWidth, minimumWidth), Layout.maxColumnWidth)
        }
        guard let width, width.isFinite, width > 0 else { return naturalWidths }

        let naturalTotal = naturalWidths.reduce(0, +)
        guard naturalTotal > 0, naturalTotal < width else { return naturalWidths }

        let extraWidth = width - naturalTotal
        return naturalWidths.map { columnWidth in
            columnWidth + extraWidth * (columnWidth / naturalTotal)
        }
    }

    static func rowHeights(for table: RenderedTableBlock, columnWidths: [CGFloat]) -> [CGFloat] {
        table.rows.map { row in
            let estimatedHeight = row.cells.enumerated().map { columnIndex, cell in
                let textHeight = measuredTextHeight(
                    for: cell.text,
                    isHeader: row.isHeader || cell.isHeader,
                    columnWidth: columnWidths[safe: columnIndex] ?? Layout.minColumnWidth
                )
                if cell.imageURL != nil {
                    let textSpacing: CGFloat = cell.text.isEmpty ? 0 : 6
                    return imageHeight + textSpacing + textHeight + Layout.verticalPadding
                }

                return textHeight + Layout.verticalPadding
            }.max() ?? defaultRowHeight

            return ceil(max(estimatedHeight, row.isHeader ? 42 : defaultRowHeight))
        }
    }

    private static func measuredTextHeight(for text: String, isHeader: Bool, columnWidth: CGFloat) -> CGFloat {
        guard text.isEmpty == false else { return 0 }

        let usableWidth = max(columnWidth - Layout.horizontalPadding, 1)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        let font = isHeader
            ? UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
            : UIFont.preferredFont(forTextStyle: .subheadline)
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: usableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ],
            context: nil
        )
        return max(ceil(bounds.height), Layout.estimatedLineHeight)
    }

    private static func resolvedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return Layout.fallbackWidth }
        return width
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}

private extension UIView {
    func debugTapFirstTableLink() -> Bool {
        if let tappable = self as? DetailTableLinkDebugTappable,
           tappable.debugTapFirstLink() {
            return true
        }
        for subview in subviews {
            if subview.debugTapFirstTableLink() {
                return true
            }
        }
        return false
    }
}

private extension RenderedTableBlock {
    var imageURLs: [URL] {
        rows.flatMap { row in
            row.cells.compactMap(\.imageURL)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
