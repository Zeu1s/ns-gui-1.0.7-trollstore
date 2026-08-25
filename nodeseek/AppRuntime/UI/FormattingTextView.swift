//
//  FormattingTextView.swift
//  nodeseek
//

import UIKit

/// 为论坛编辑器补充与 iOS 文本选择菜单一致的常用排版能力。
/// 发送时将当前富文本转换为 NodeSeek 可接受的 HTML 片段。
final class FormattingTextView: UITextView {
    private struct TextStyle: Equatable {
        let isBold: Bool
        let isItalic: Bool
        let isUnderlined: Bool
        let isStruckThrough: Bool
        let indentationLevel: Int
    }

    private enum InlineFormatControl: Hashable {
        case bold
        case italic
        case underline
        case strikethrough
    }

    private var inlineFormatButtons: [InlineFormatControl: UIButton] = [:]
    private var supplementaryAccessoryItems: [UIBarButtonItem] = []

    /// 仅在用户执行“粘贴”时调用，不会读取或监听剪贴板。
    var onPasteImage: ((UIImage) -> Bool)?

    override var selectedRange: NSRange {
        didSet {
            guard selectedRange != oldValue else { return }
            synchronizeInlineFormatButtons()
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureFormattingMenu()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureFormattingMenu()
    }

    /// 供外层编辑器添加图片等业务入口，同时保留四个常用格式按钮。
    func setSupplementaryAccessoryItems(_ items: [UIBarButtonItem]) {
        supplementaryAccessoryItems = items
        rebuildFormattingToolbar()
        if isFirstResponder {
            reloadInputViews()
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(cut(_:))
            || action == #selector(copy(_:))
            || action == #selector(selectAll(_:))
            || action == NSSelectorFromString("lookup:")
            || action == NSSelectorFromString("translate:") {
            // 用同功能的中文菜单替代系统按设备语言显示的英文标题。
            return false
        }
        switch action {
        case #selector(cutSelection(_:)),
             #selector(copySelection(_:)),
             #selector(selectAllText(_:)),
             #selector(lookupSelection(_:)),
             #selector(translateSelection(_:)):
            return selectedRange.length > 0
        case #selector(toggleBoldFormatting(_:)),
             #selector(toggleItalicFormatting(_:)),
             #selector(toggleUnderlineFormatting(_:)),
             #selector(toggleStrikethroughFormatting(_:)),
             #selector(increaseIndentation(_:)),
             #selector(decreaseIndentation(_:)):
            return isEditable
        case #selector(applyHeadingFormatting(_:)),
             #selector(applyUnorderedListFormatting(_:)),
             #selector(applyOrderedListFormatting(_:)),
             #selector(applyQuoteFormatting(_:)),
             #selector(applyInlineCodeFormatting(_:)),
             #selector(applyCodeBlockFormatting(_:)),
             #selector(insertLinkFormatting(_:)),
             #selector(clearFormatting(_:)):
            return isEditable && selectedRange.length > 0
        case #selector(insertTableFormatting(_:)),
             #selector(insertHorizontalRuleFormatting(_:)):
            return isEditable
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard isEditable else { return }

        let editMenu = UIMenu(
            title: "编辑",
            image: nil,
            identifier: UIMenu.Identifier("com.zeu1s.nodeseek.text-edit"),
            options: .displayInline,
            children: [
                UICommand(title: "剪切", image: UIImage(systemName: "scissors"), action: #selector(cutSelection(_:))),
                UICommand(title: "复制", image: UIImage(systemName: "doc.on.doc"), action: #selector(copySelection(_:))),
                UICommand(title: "全选", image: UIImage(systemName: "selection.pin.in.out"), action: #selector(selectAllText(_:))),
                UICommand(title: "查询", image: UIImage(systemName: "book"), action: #selector(lookupSelection(_:))),
                UICommand(title: "翻译", image: UIImage(systemName: "character.book.closed"), action: #selector(translateSelection(_:)))
            ]
        )
        builder.insertChild(editMenu, atStartOfMenu: .edit)

        let menu = UIMenu(
            title: "格式",
            image: nil,
            identifier: UIMenu.Identifier("com.zeu1s.nodeseek.text-format"),
            options: [],
            children: [
                UICommand(
                    title: "粗体",
                    image: UIImage(systemName: "bold"),
                    action: #selector(toggleBoldFormatting(_:))
                ),
                UICommand(
                    title: "斜体",
                    image: UIImage(systemName: "italic"),
                    action: #selector(toggleItalicFormatting(_:))
                ),
                UICommand(
                    title: "下划线",
                    image: UIImage(systemName: "underline"),
                    action: #selector(toggleUnderlineFormatting(_:))
                ),
                UICommand(
                    title: "删除线",
                    image: UIImage(systemName: "strikethrough"),
                    action: #selector(toggleStrikethroughFormatting(_:))
                ),
                UICommand(
                    title: "增加缩进",
                    image: UIImage(systemName: "increase.indent"),
                    action: #selector(increaseIndentation(_:))
                ),
                UICommand(
                    title: "减少缩进",
                    image: UIImage(systemName: "decrease.indent"),
                    action: #selector(decreaseIndentation(_:))
                ),
                UICommand(
                    title: "标题",
                    image: UIImage(systemName: "textformat.size"),
                    action: #selector(applyHeadingFormatting(_:))
                ),
                UICommand(
                    title: "无序列表",
                    image: UIImage(systemName: "list.bullet"),
                    action: #selector(applyUnorderedListFormatting(_:))
                ),
                UICommand(
                    title: "有序列表",
                    image: UIImage(systemName: "list.number"),
                    action: #selector(applyOrderedListFormatting(_:))
                ),
                UICommand(
                    title: "引用",
                    image: UIImage(systemName: "text.quote"),
                    action: #selector(applyQuoteFormatting(_:))
                ),
                UICommand(
                    title: "行内代码",
                    image: UIImage(systemName: "chevron.left.forwardslash.chevron.right"),
                    action: #selector(applyInlineCodeFormatting(_:))
                ),
                UICommand(
                    title: "代码块",
                    image: UIImage(systemName: "curlybraces"),
                    action: #selector(applyCodeBlockFormatting(_:))
                ),
                UICommand(
                    title: "链接",
                    image: UIImage(systemName: "link"),
                    action: #selector(insertLinkFormatting(_:))
                ),
                UICommand(
                    title: "插入表格",
                    image: UIImage(systemName: "tablecells"),
                    action: #selector(insertTableFormatting(_:))
                ),
                UICommand(
                    title: "分隔线",
                    image: UIImage(systemName: "minus"),
                    action: #selector(insertHorizontalRuleFormatting(_:))
                ),
                UICommand(
                    title: "清除格式",
                    image: UIImage(systemName: "clear"),
                    action: #selector(clearFormatting(_:))
                )
            ]
        )
        builder.insertChild(menu, atStartOfMenu: .edit)
    }

    override func paste(_ sender: Any?) {
        if isEditable,
           let image = UIPasteboard.general.image,
           onPasteImage?(image) == true {
            return
        }
        super.paste(sender)
    }

    /// 将界面上的格式转换为提交内容。NodeSeek 原生 HTML 渲染支持这些标签。
    func formattedSubmissionText() -> String {
        let source = attributedText ?? NSAttributedString()
        guard source.length > 0 else { return "" }

        var result = ""
        var activeStyle: TextStyle?
        let range = NSRange(location: 0, length: source.length)
        source.enumerateAttributes(in: range, options: []) { attributes, attributeRange, _ in
            let style = Self.style(from: attributes, fallbackFont: self.font)
            if style != activeStyle {
                if let activeStyle {
                    result += Self.closingMarkup(for: activeStyle)
                }
                result += Self.openingMarkup(for: style)
                activeStyle = style
            }
            result += source.attributedSubstring(from: attributeRange).string
        }
        if let activeStyle {
            result += Self.closingMarkup(for: activeStyle)
        }
        return result
    }

    @objc private func toggleBoldFormatting(_ sender: Any?) {
        updateSelectionStyle { style in
            TextStyle(
                isBold: !style.isBold,
                isItalic: style.isItalic,
                isUnderlined: style.isUnderlined,
                isStruckThrough: style.isStruckThrough,
                indentationLevel: style.indentationLevel
            )
        }
    }

    @objc private func cutSelection(_ sender: Any?) {
        cut(sender)
    }

    @objc private func copySelection(_ sender: Any?) {
        copy(sender)
    }

    @objc private func selectAllText(_ sender: Any?) {
        selectAll(sender)
    }

    @objc private func lookupSelection(_ sender: Any?) {
        let source = text ?? ""
        let selection = safeSelectedRange(in: attributedText ?? NSAttributedString())
        let selectedText = (source as NSString)
            .substring(with: selection)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedText.isEmpty == false,
              UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: selectedText) else { return }
        containingViewController()?.present(
            UIReferenceLibraryViewController(term: selectedText),
            animated: true
        )
    }

    @objc private func translateSelection(_ sender: Any?) {
        let translationSelector = NSSelectorFromString("translate:")
        guard responds(to: translationSelector) else { return }
        perform(translationSelector, with: sender)
    }

    @objc private func toggleItalicFormatting(_ sender: Any?) {
        updateSelectionStyle { style in
            TextStyle(
                isBold: style.isBold,
                isItalic: !style.isItalic,
                isUnderlined: style.isUnderlined,
                isStruckThrough: style.isStruckThrough,
                indentationLevel: style.indentationLevel
            )
        }
    }

    @objc private func toggleUnderlineFormatting(_ sender: Any?) {
        updateSelectionStyle { style in
            TextStyle(
                isBold: style.isBold,
                isItalic: style.isItalic,
                isUnderlined: !style.isUnderlined,
                isStruckThrough: style.isStruckThrough,
                indentationLevel: style.indentationLevel
            )
        }
    }

    @objc private func toggleStrikethroughFormatting(_ sender: Any?) {
        updateSelectionStyle { style in
            TextStyle(
                isBold: style.isBold,
                isItalic: style.isItalic,
                isUnderlined: style.isUnderlined,
                isStruckThrough: !style.isStruckThrough,
                indentationLevel: style.indentationLevel
            )
        }
    }

    @objc private func increaseIndentation(_ sender: Any?) {
        updateSelectionStyle { style in
            TextStyle(
                isBold: style.isBold,
                isItalic: style.isItalic,
                isUnderlined: style.isUnderlined,
                isStruckThrough: style.isStruckThrough,
                indentationLevel: min(style.indentationLevel + 1, 4)
            )
        }
    }

    @objc private func decreaseIndentation(_ sender: Any?) {
        updateSelectionStyle { style in
            TextStyle(
                isBold: style.isBold,
                isItalic: style.isItalic,
                isUnderlined: style.isUnderlined,
                isStruckThrough: style.isStruckThrough,
                indentationLevel: max(style.indentationLevel - 1, 0)
            )
        }
    }

    @objc private func applyHeadingFormatting(_ sender: Any?) {
        prefixSelectedLines { _ in "## " }
    }

    @objc private func applyUnorderedListFormatting(_ sender: Any?) {
        prefixSelectedLines { _ in "- " }
    }

    @objc private func applyOrderedListFormatting(_ sender: Any?) {
        prefixSelectedLines { index in "\(index + 1). " }
    }

    @objc private func applyQuoteFormatting(_ sender: Any?) {
        prefixSelectedLines { _ in "> " }
    }

    @objc private func applyInlineCodeFormatting(_ sender: Any?) {
        wrapSelectedText(withPrefix: "`", suffix: "`")
    }

    @objc private func applyCodeBlockFormatting(_ sender: Any?) {
        wrapSelectedText(withPrefix: "```\n", suffix: "\n```")
    }

    @objc private func insertLinkFormatting(_ sender: Any?) {
        guard let controller = containingViewController(), selectedRange.length > 0 else { return }

        let alert = UIAlertController(title: "插入链接", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "https://example.com"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "插入", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let destination = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  URL(string: destination)?.scheme?.isEmpty == false else {
                return
            }
            self.wrapSelectedText(withPrefix: "[", suffix: "](\(destination))")
        })
        controller.present(alert, animated: true)
    }

    @objc private func insertTableFormatting(_ sender: Any?) {
        replaceSelection(with: "| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |")
    }

    @objc private func insertHorizontalRuleFormatting(_ sender: Any?) {
        replaceSelection(with: "\n\n---\n\n")
    }

    @objc private func clearFormatting(_ sender: Any?) {
        let source = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
        let range = safeSelectedRange(in: source)
        guard range.length > 0 else { return }

        let plainAttributes = plainTextAttributes()
        source.setAttributes(plainAttributes, range: range)
        attributedText = source
        selectedRange = range
        typingAttributes = plainAttributes
        synchronizeInlineFormatButtons()
    }

    private func configureFormattingMenu() {
        rebuildFormattingToolbar()

        // iOS 15 仍使用 UIMenuController 展示编辑菜单；iOS 16+ 由 buildMenu 提供。
        if #unavailable(iOS 16.0) {
            UIMenuController.shared.menuItems = [
                UIMenuItem(title: "剪切", action: #selector(cutSelection(_:))),
                UIMenuItem(title: "复制", action: #selector(copySelection(_:))),
                UIMenuItem(title: "全选", action: #selector(selectAllText(_:))),
                UIMenuItem(title: "查询", action: #selector(lookupSelection(_:))),
                UIMenuItem(title: "翻译", action: #selector(translateSelection(_:))),
                UIMenuItem(title: "粗体", action: #selector(toggleBoldFormatting(_:))),
                UIMenuItem(title: "斜体", action: #selector(toggleItalicFormatting(_:))),
                UIMenuItem(title: "下划线", action: #selector(toggleUnderlineFormatting(_:))),
                UIMenuItem(title: "删除线", action: #selector(toggleStrikethroughFormatting(_:))),
                UIMenuItem(title: "增加缩进", action: #selector(increaseIndentation(_:))),
                UIMenuItem(title: "减少缩进", action: #selector(decreaseIndentation(_:))),
                UIMenuItem(title: "标题", action: #selector(applyHeadingFormatting(_:))),
                UIMenuItem(title: "无序列表", action: #selector(applyUnorderedListFormatting(_:))),
                UIMenuItem(title: "有序列表", action: #selector(applyOrderedListFormatting(_:))),
                UIMenuItem(title: "引用", action: #selector(applyQuoteFormatting(_:))),
                UIMenuItem(title: "行内代码", action: #selector(applyInlineCodeFormatting(_:))),
                UIMenuItem(title: "代码块", action: #selector(applyCodeBlockFormatting(_:))),
                UIMenuItem(title: "链接", action: #selector(insertLinkFormatting(_:))),
                UIMenuItem(title: "插入表格", action: #selector(insertTableFormatting(_:))),
                UIMenuItem(title: "分隔线", action: #selector(insertHorizontalRuleFormatting(_:))),
                UIMenuItem(title: "清除格式", action: #selector(clearFormatting(_:)))
            ]
        }
    }

    private lazy var formattingToolbar = UIToolbar()

    private func rebuildFormattingToolbar() {
        inlineFormatButtons.removeAll()
        var items: [UIBarButtonItem] = [
            toolbarButton(
                control: .bold,
                imageName: "bold",
                action: #selector(toggleBoldFormatting(_:)),
                label: "粗体"
            ),
            toolbarButton(
                control: .italic,
                imageName: "italic",
                action: #selector(toggleItalicFormatting(_:)),
                label: "斜体"
            ),
            toolbarButton(
                control: .underline,
                imageName: "underline",
                action: #selector(toggleUnderlineFormatting(_:)),
                label: "下划线"
            ),
            toolbarButton(
                control: .strikethrough,
                imageName: "strikethrough",
                action: #selector(toggleStrikethroughFormatting(_:)),
                label: "删除线"
            )
        ]
        items.append(contentsOf: supplementaryAccessoryItems)
        items.append(UIBarButtonItem(systemItem: .flexibleSpace))
        items.append(additionalFormattingButton())
        formattingToolbar.setItems(items, animated: false)
        formattingToolbar.sizeToFit()
        inputAccessoryView = formattingToolbar
        synchronizeInlineFormatButtons()
    }

    private func toolbarButton(
        control: InlineFormatControl,
        imageName: String,
        action: Selector,
        label: String
    ) -> UIBarButtonItem {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: imageName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 7, bottom: 6, trailing: 7)
        configuration.background.cornerRadius = 6
        button.configuration = configuration
        button.accessibilityLabel = label
        button.accessibilityIdentifier = "formatting-text-view-\(label)"
        button.addTarget(self, action: action, for: .touchUpInside)
        inlineFormatButtons[control] = button
        update(button: button, isActive: false)
        return UIBarButtonItem(customView: button)
    }

    private func synchronizeInlineFormatButtons() {
        let style = currentSelectionStyle()
        update(button: inlineFormatButtons[.bold], isActive: style.isBold)
        update(button: inlineFormatButtons[.italic], isActive: style.isItalic)
        update(button: inlineFormatButtons[.underline], isActive: style.isUnderlined)
        update(button: inlineFormatButtons[.strikethrough], isActive: style.isStruckThrough)
    }

    private func update(button: UIButton?, isActive: Bool) {
        guard let button else { return }
        button.isSelected = isActive
        var configuration = button.configuration ?? UIButton.Configuration.plain()
        configuration.baseForegroundColor = isActive ? .systemOrange : .secondaryLabel
        configuration.background.backgroundColor = isActive ? UIColor.systemOrange.withAlphaComponent(0.16) : .clear
        button.configuration = configuration
        button.accessibilityValue = isActive ? "已启用" : "未启用"
    }

    private func currentSelectionStyle() -> TextStyle {
        let source = attributedText ?? NSAttributedString()
        let selection = safeSelectedRange(in: source)
        if selection.length > 0 {
            return styleForSelection(in: source, range: selection)
        }
        if typingAttributes.isEmpty == false {
            return Self.style(from: typingAttributes, fallbackFont: font)
        }
        guard source.length > 0 else {
            return Self.style(from: plainTextAttributes(), fallbackFont: font)
        }
        let location = min(max(selection.location, 0), source.length - 1)
        return Self.style(
            from: source.attributes(at: location, effectiveRange: nil),
            fallbackFont: font
        )
    }

    private func additionalFormattingButton() -> UIBarButtonItem {
        let button = UIBarButtonItem(image: UIImage(systemName: "textformat"), menu: additionalFormattingMenu())
        button.accessibilityLabel = "更多格式"
        return button
    }

    private func additionalFormattingMenu() -> UIMenu {
        UIMenu(title: "更多格式", children: [
            formatAction(title: "标题", imageName: "textformat.size", selector: #selector(applyHeadingFormatting(_:))),
            formatAction(title: "无序列表", imageName: "list.bullet", selector: #selector(applyUnorderedListFormatting(_:))),
            formatAction(title: "有序列表", imageName: "list.number", selector: #selector(applyOrderedListFormatting(_:))),
            formatAction(title: "引用", imageName: "text.quote", selector: #selector(applyQuoteFormatting(_:))),
            formatAction(title: "行内代码", imageName: "chevron.left.forwardslash.chevron.right", selector: #selector(applyInlineCodeFormatting(_:))),
            formatAction(title: "代码块", imageName: "curlybraces", selector: #selector(applyCodeBlockFormatting(_:))),
            formatAction(title: "链接", imageName: "link", selector: #selector(insertLinkFormatting(_:))),
            formatAction(title: "插入表格", imageName: "tablecells", selector: #selector(insertTableFormatting(_:))),
            formatAction(title: "分隔线", imageName: "minus", selector: #selector(insertHorizontalRuleFormatting(_:))),
            formatAction(title: "清除格式", imageName: "clear", selector: #selector(clearFormatting(_:)))
        ])
    }

    private func formatAction(title: String, imageName: String, selector: Selector) -> UIAction {
        UIAction(title: title, image: UIImage(systemName: imageName)) { [weak self] _ in
            _ = self?.perform(selector, with: nil)
        }
    }

    private func prefixSelectedLines(_ prefix: (Int) -> String) {
        let source = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
        let selection = safeSelectedRange(in: source)
        guard selection.length > 0 else { return }

        let lineStarts = lineStartsIntersectingSelection(in: source.string as NSString, selection: selection)
        guard lineStarts.isEmpty == false else { return }

        var insertedLength = 0
        for (lineIndex, lineStart) in lineStarts.enumerated().reversed() {
            let value = prefix(lineIndex)
            insertedLength += (value as NSString).length
            source.insert(
                NSAttributedString(string: value, attributes: plainTextAttributes()),
                at: lineStart
            )
        }
        attributedText = source
        selectedRange = NSRange(location: selection.location, length: selection.length + insertedLength)
        synchronizeInlineFormatButtons()
    }

    private func wrapSelectedText(withPrefix prefix: String, suffix: String) {
        let source = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
        let selection = safeSelectedRange(in: source)
        guard selection.length > 0 else { return }

        let selectionText = source.attributedSubstring(from: selection)
        let replacement = NSMutableAttributedString(string: prefix, attributes: plainTextAttributes())
        replacement.append(selectionText)
        replacement.append(NSAttributedString(string: suffix, attributes: plainTextAttributes()))
        source.replaceCharacters(in: selection, with: replacement)
        attributedText = source
        selectedRange = NSRange(
            location: selection.location + (prefix as NSString).length,
            length: selection.length
        )
        synchronizeInlineFormatButtons()
    }

    private func replaceSelection(with text: String) {
        let source = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
        let selection = safeSelectedRange(in: source)
        source.replaceCharacters(
            in: selection,
            with: NSAttributedString(string: text, attributes: plainTextAttributes())
        )
        attributedText = source
        selectedRange = NSRange(location: selection.location + (text as NSString).length, length: 0)
        typingAttributes = plainTextAttributes()
        synchronizeInlineFormatButtons()
    }

    private func safeSelectedRange(in text: NSAttributedString) -> NSRange {
        let location = min(max(selectedRange.location, 0), text.length)
        let length = min(max(selectedRange.length, 0), text.length - location)
        return NSRange(location: location, length: length)
    }

    private func lineStartsIntersectingSelection(in text: NSString, selection: NSRange) -> [Int] {
        guard text.length > 0 else { return [] }

        let firstLocation = min(selection.location, text.length - 1)
        let lastLocation = min(max(NSMaxRange(selection) - 1, firstLocation), text.length - 1)
        var cursor = text.lineRange(for: NSRange(location: firstLocation, length: 0)).location
        let selectionEnd = NSMaxRange(text.lineRange(for: NSRange(location: lastLocation, length: 0)))
        var lineStarts: [Int] = []

        while cursor < selectionEnd {
            lineStarts.append(cursor)
            let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
            let nextCursor = NSMaxRange(lineRange)
            guard nextCursor > cursor else { break }
            cursor = nextCursor
        }
        return lineStarts
    }

    private func plainTextAttributes() -> [NSAttributedString.Key: Any] {
        let baseFont = font ?? UIFont.preferredFont(forTextStyle: .body)
        return [
            .font: Self.font(from: baseFont, isBold: false, isItalic: false),
            .foregroundColor: textColor ?? UIColor.label,
            .paragraphStyle: Self.paragraphStyle(from: nil, indentationLevel: 0)
        ]
    }

    private func containingViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }

    private func updateSelectionStyle(_ transform: (TextStyle) -> TextStyle) {
        let source = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
        let selectedRange = safeSelectedRange(in: source)
        let selectionStyle = currentSelectionStyle()
        let targetStyle = transform(selectionStyle)

        guard selectedRange.length > 0 else {
            let baseAttributes = typingAttributes.isEmpty ? plainTextAttributes() : typingAttributes
            typingAttributes = attributes(baseAttributes, applying: targetStyle)
            synchronizeInlineFormatButtons()
            return
        }

        var attributeRanges: [(NSRange, [NSAttributedString.Key: Any])] = []
        source.enumerateAttributes(in: selectedRange, options: []) { attributes, range, _ in
            attributeRanges.append((range, attributes))
        }
        for (range, attributes) in attributeRanges {
            source.setAttributes(self.attributes(attributes, applying: targetStyle), range: range)
        }

        attributedText = source
        self.selectedRange = selectedRange
        if source.length > 0 {
            let typingLocation = min(selectedRange.location, source.length - 1)
            typingAttributes = source.attributes(at: typingLocation, effectiveRange: nil)
        }
        synchronizeInlineFormatButtons()
    }

    private func attributes(
        _ source: [NSAttributedString.Key: Any],
        applying style: TextStyle
    ) -> [NSAttributedString.Key: Any] {
        var attributes = source
        let baseFont = (attributes[.font] as? UIFont) ?? font ?? UIFont.preferredFont(forTextStyle: .body)
        attributes[.font] = Self.font(from: baseFont, isBold: style.isBold, isItalic: style.isItalic)
        if style.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes.removeValue(forKey: .underlineStyle)
        }
        if style.isStruckThrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes.removeValue(forKey: .strikethroughStyle)
        }
        attributes[.paragraphStyle] = Self.paragraphStyle(
            from: attributes[.paragraphStyle],
            indentationLevel: style.indentationLevel
        )
        return attributes
    }

    private func styleForSelection(in text: NSAttributedString, range: NSRange) -> TextStyle {
        var isBold = true
        var isItalic = true
        var isUnderlined = true
        var isStruckThrough = true
        var indentationLevel = Int.max
        let fallbackFont = font ?? UIFont.preferredFont(forTextStyle: .body)
        text.enumerateAttributes(in: range, options: []) { attributes, _, _ in
            let style = Self.style(from: attributes, fallbackFont: fallbackFont)
            isBold = isBold && style.isBold
            isItalic = isItalic && style.isItalic
            isUnderlined = isUnderlined && style.isUnderlined
            isStruckThrough = isStruckThrough && style.isStruckThrough
            indentationLevel = min(indentationLevel, style.indentationLevel)
        }
        return TextStyle(
            isBold: isBold,
            isItalic: isItalic,
            isUnderlined: isUnderlined,
            isStruckThrough: isStruckThrough,
            indentationLevel: indentationLevel == Int.max ? 0 : indentationLevel
        )
    }

    private static func style(from attributes: [NSAttributedString.Key: Any], fallbackFont: UIFont?) -> TextStyle {
        let font = (attributes[.font] as? UIFont) ?? fallbackFont ?? UIFont.preferredFont(forTextStyle: .body)
        let isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
        let isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        let underline = (attributes[.underlineStyle] as? Int) ?? 0
        let strikethrough = (attributes[.strikethroughStyle] as? Int) ?? 0
        let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        return TextStyle(
            isBold: isBold,
            isItalic: isItalic,
            isUnderlined: underline != 0,
            isStruckThrough: strikethrough != 0,
            indentationLevel: indentationLevel(from: paragraphStyle)
        )
    }

    private static func font(from font: UIFont, isBold: Bool, isItalic: Bool) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if isBold {
            traits.insert(.traitBold)
        } else {
            traits.remove(.traitBold)
        }
        if isItalic {
            traits.insert(.traitItalic)
        } else {
            traits.remove(.traitItalic)
        }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else {
            let fallback = isBold ? UIFont.boldSystemFont(ofSize: font.pointSize) : UIFont.systemFont(ofSize: font.pointSize)
            guard isItalic,
                  let italicDescriptor = fallback.fontDescriptor.withSymbolicTraits(
                    fallback.fontDescriptor.symbolicTraits.union(.traitItalic)
                  ) else {
                return fallback
            }
            return UIFont(descriptor: italicDescriptor, size: font.pointSize)
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private static func paragraphStyle(from value: Any?, indentationLevel: Int) -> NSParagraphStyle {
        let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        let indent = CGFloat(indentationLevel) * 22
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    private static func indentationLevel(from style: NSParagraphStyle?) -> Int {
        guard let style else { return 0 }
        return max(0, Int((max(style.firstLineHeadIndent, style.headIndent) / 22).rounded()))
    }

    private static func openingMarkup(for style: TextStyle) -> String {
        var markup = ""
        for _ in 0..<style.indentationLevel {
            markup += "<blockquote>"
        }
        if style.isBold {
            markup += "<strong>"
        }
        if style.isItalic {
            markup += "<em>"
        }
        if style.isUnderlined {
            markup += "<u>"
        }
        if style.isStruckThrough {
            markup += "<s>"
        }
        return markup
    }

    private static func closingMarkup(for style: TextStyle) -> String {
        var markup = ""
        if style.isStruckThrough {
            markup += "</s>"
        }
        if style.isUnderlined {
            markup += "</u>"
        }
        if style.isItalic {
            markup += "</em>"
        }
        if style.isBold {
            markup += "</strong>"
        }
        for _ in 0..<style.indentationLevel {
            markup += "</blockquote>"
        }
        return markup
    }

    /// 图片和表情插入时保留用户已有的富文本属性，避免覆盖已选中的格式。
    func insertSubmissionText(_ text: String, separatedByNewlines: Bool = false) {
        guard text.isEmpty == false else { return }

        let sourceText = self.text ?? ""
        let sourceLength = (sourceText as NSString).length
        let safeLocation = min(max(selectedRange.location, 0), sourceLength)
        let safeLength = min(max(selectedRange.length, 0), sourceLength - safeLocation)
        let replacementRange = NSRange(location: safeLocation, length: safeLength)
        let prefix = (sourceText as NSString).substring(to: safeLocation)
        let suffix = (sourceText as NSString).substring(from: NSMaxRange(replacementRange))
        let insertedText: String
        if separatedByNewlines {
            insertedText = [
                prefix.isEmpty == false && prefix.last?.isNewline == false ? "\n" : "",
                text,
                suffix.isEmpty == false && suffix.first?.isNewline == false ? "\n" : ""
            ].joined()
        } else {
            insertedText = text
        }

        let source = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
        var attributes = typingAttributes
        if attributes.isEmpty {
            attributes = plainTextAttributes()
        }
        attributes[.foregroundColor] = textColor ?? UIColor.label
        source.replaceCharacters(in: replacementRange, with: NSAttributedString(string: insertedText, attributes: attributes))
        attributedText = source
        selectedRange = NSRange(location: safeLocation + (insertedText as NSString).length, length: 0)
        typingAttributes = attributes
        synchronizeInlineFormatButtons()
    }
}
