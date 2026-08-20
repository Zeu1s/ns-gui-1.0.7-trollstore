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

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureFormattingMenu()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureFormattingMenu()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(toggleBoldFormatting(_:)),
             #selector(toggleItalicFormatting(_:)),
             #selector(toggleUnderlineFormatting(_:)),
             #selector(toggleStrikethroughFormatting(_:)),
             #selector(increaseIndentation(_:)),
             #selector(decreaseIndentation(_:)),
             #selector(applyHeadingFormatting(_:)),
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
        builder.insertChild(menu, atEndOfMenu: .edit)
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
    }

    private func configureFormattingMenu() {
        // iOS 15 仍使用 UIMenuController 展示编辑菜单；iOS 16+ 由 buildMenu 提供。
        if #unavailable(iOS 16.0) {
            UIMenuController.shared.menuItems = [
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
        let selectedRange = selectedRange
        guard selectedRange.length > 0 else { return }

        let source = NSMutableAttributedString(attributedString: attributedText ?? NSAttributedString())
        let selectionStyle = styleForSelection(in: source, range: selectedRange)
        let targetStyle = transform(selectionStyle)
        let fallbackFont = font ?? UIFont.preferredFont(forTextStyle: .body)

        var fontRanges: [(NSRange, UIFont)] = []
        source.enumerateAttributes(in: selectedRange, options: []) { attributes, range, _ in
            let currentFont = (attributes[.font] as? UIFont) ?? fallbackFont
            fontRanges.append((range, currentFont))
        }
        for (range, currentFont) in fontRanges {
            source.addAttribute(
                .font,
                value: Self.font(from: currentFont, isBold: targetStyle.isBold, isItalic: targetStyle.isItalic),
                range: range
            )
            if targetStyle.isUnderlined {
                source.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                source.removeAttribute(.underlineStyle, range: range)
            }
            if targetStyle.isStruckThrough {
                source.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                source.removeAttribute(.strikethroughStyle, range: range)
            }
            source.addAttribute(
                .paragraphStyle,
                value: Self.paragraphStyle(
                    from: source.attribute(.paragraphStyle, at: range.location, effectiveRange: nil),
                    indentationLevel: targetStyle.indentationLevel
                ),
                range: range
            )
        }

        attributedText = source
        self.selectedRange = selectedRange
        if source.length > 0 {
            let typingLocation = min(selectedRange.location, source.length - 1)
            typingAttributes = source.attributes(at: typingLocation, effectiveRange: nil)
        }
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
            isUnderlined: underline != NSUnderlineStyle.none.rawValue,
            isStruckThrough: strikethrough != NSUnderlineStyle.none.rawValue,
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
        let baseFont = font ?? UIFont.preferredFont(forTextStyle: .body)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font(from: baseFont, isBold: false, isItalic: false),
            .foregroundColor: textColor ?? UIColor.label
        ]
        source.replaceCharacters(in: replacementRange, with: NSAttributedString(string: insertedText, attributes: attributes))
        attributedText = source
        selectedRange = NSRange(location: safeLocation + (insertedText as NSString).length, length: 0)
        typingAttributes = attributes
    }
}
