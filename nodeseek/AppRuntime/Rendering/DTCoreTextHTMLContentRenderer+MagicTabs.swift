//
//  DTCoreTextHTMLContentRenderer+MagicTabs.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import Foundation
import Kanna

extension DTCoreTextHTMLContentRenderer {
    /// 将 NodeSeek 的网页标签转换为原生可切换的内容块，不再按顺序拍平所有页签。
    func renderNodeSeekMagicTabs(
        in fragment: String,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> [RenderedContentBlock]? {
        guard fragment.contains("nsk-magic-tabs"),
              let document = try? HTML(
                html: "<div id=\"__nodeseek_fragment_root__\">\(fragment)</div>",
                encoding: .utf8
              ),
              let root = document.at_css("#__nodeseek_fragment_root__") else {
            return nil
        }

        var blocks: [RenderedContentBlock] = []
        var pendingHTML = ""
        let magicTabReportURLSet = Set(root.children
            .filter { hasClass("nsk-magic-tabs", in: $0) }
            .flatMap { checkPlaceReportURLs(in: $0.innerHTML ?? $0.text ?? "") }
            .map { $0.absoluteString.lowercased() })

        func flushPendingHTML() {
            guard pendingHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                pendingHTML.removeAll(keepingCapacity: true)
                return
            }
            blocks.append(contentsOf: renderContentBlocks(
                fragment: pendingHTML,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            ))
            pendingHTML.removeAll(keepingCapacity: true)
        }

        for child in root.children {
            if hasClass("nsk-magic-tabs", in: child) {
                flushPendingHTML()
                if let tabs = magicTabsBlock(from: child, baseURL: baseURL, maxImageWidth: maxImageWidth) {
                    blocks.append(.magicTabs(tabs))
                }
            } else if let html = deduplicatedHTMLOutsideMagicTabs(
                from: child,
                matchingReportURLs: magicTabReportURLSet
            ) {
                pendingHTML.append(html)
            }
        }
        flushPendingHTML()
        return blocks.isEmpty ? nil : blocks
    }

    /// NodeQuality 的“复制 NodeSeek 格式”在部分粘贴路径中会同时保留一份普通 pre。
    /// 仅当 pre 引用了标签页内同一份 Check.Place 报告时才去除，避免吞掉作者的补充说明。
    private func deduplicatedHTMLOutsideMagicTabs(
        from node: XMLElement,
        matchingReportURLs: Set<String>
    ) -> String? {
        guard matchingReportURLs.isEmpty == false,
              var html = node.toHTML,
              html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return node.toHTML
        }

        var preNodes: [XMLElement] = []
        if isPreElement(node) {
            preNodes.append(node)
        }
        preNodes.append(contentsOf: node.css("pre"))

        for preNode in preNodes where isDuplicateMagicTabReport(
            in: preNode,
            matchingReportURLs: matchingReportURLs
        ) {
            guard let preHTML = preNode.toHTML else { continue }
            html = html.replacingOccurrences(of: preHTML, with: "")
        }

        return html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : html
    }

    private func isDuplicateMagicTabReport(
        in preNode: XMLElement,
        matchingReportURLs: Set<String>
    ) -> Bool {
        guard let codeBlock = codeBlock(from: preNode) else { return false }
        let reportURLs = Set(checkPlaceReportURLs(in: codeBlock.text).map {
            $0.absoluteString.lowercased()
        })
        return reportURLs.isDisjoint(with: matchingReportURLs) == false
    }

    private func magicTabsBlock(
        from node: XMLElement,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> RenderedMagicTabsBlock? {
        var tabs: [RenderedMagicTab] = []
        var pendingTitle: String?

        for child in node.children {
            if hasClass("nsk-magic-tab-title", in: child) {
                pendingTitle = child.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            guard hasClass("nsk-magic-tab-body", in: child),
                  let title = pendingTitle,
                  title.isEmpty == false else {
                continue
            }
            let bodyHTML = child.innerHTML ?? child.text ?? ""
            let blocks = magicTabContentBlocks(
                from: bodyHTML,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            )
            if blocks.isEmpty == false {
                tabs.append(RenderedMagicTab(title: title, blocks: blocks))
            }
            pendingTitle = nil
        }

        guard tabs.isEmpty == false else { return nil }
        return RenderedMagicTabsBlock(tabs: tabs)
    }

    /// 保留标签页的原始顺序，避免“全部”页把多个测评输出混在同一屏。
    /// NodeQuality 的终端输出以彩色终端为主（还原 ANSI 背景色），
    /// 同一份 Check.Place 报告图保留在终端下方，可点开查看大图。
    private func magicTabContentBlocks(
        from bodyHTML: String,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> [RenderedContentBlock] {
        // 原来这里扫了两遍整页 HTML（一次建图块、一次建 URL 集合），合成一次。
        let discoveredReportURLs = checkPlaceReportURLs(in: bodyHTML)
        let reportURLs = Set(discoveredReportURLs.map { $0.absoluteString.lowercased() })
        var seenReportURLs = Set<String>()
        let reportImageBlocks = discoveredReportURLs.compactMap { url -> RenderedContentBlock? in
            guard seenReportURLs.insert(url.absoluteString.lowercased()).inserted else { return nil }
            return .image(RenderedImageBlock(url: url, altText: "NodeQuality 测试报告"))
        }
        let terminalBlocks = xtermMagicTabCodeBlock(from: bodyHTML).map { [$0] }
            ?? ansiMagicTabCodeBlocks(from: bodyHTML)
        if terminalBlocks.isEmpty == false {
            // 有终端文本就只出终端文本，不再放 Check.Place 报告图。
            // 报告 SVG 要靠 SVGKit 光栅化，而它的颜色写在 <style> 的类选择器里、
            // 归一化器从不内联，真机上是两种坏结果并存：整块纯黑（类丢失后
            // 黑底黑字），或能看见但很糊（缩略图分支写死 scale=1 加 JPEG，
            // 3 倍屏按 1 倍画，点开全屏查看器才按原始尺寸重绘所以变清晰）。
            // 终端文本是原生绘制的，清晰且颜色正确。没有终端文本的帖子仍走
            // 下面的图片分支，不至于什么都不显示。
            let authoredImages = promotableImageBlocks(in: bodyHTML)
                .filter { reportURLs.contains($0.url.absoluteString.lowercased()) == false }
                .map(RenderedContentBlock.image)
            return terminalBlocks.map { RenderedContentBlock.codeBlock($0) } + authoredImages
        }

        let renderedBlocks = renderContentBlocks(
            fragment: simplifiedMagicTabBodyHTML(bodyHTML),
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        ).filter { block in
            guard case let .image(image) = block else { return true }
            return reportURLs.contains(image.url.absoluteString.lowercased()) == false
        }
        return renderedBlocks + reportImageBlocks
    }

    func expandNodeSeekMagicTabs(in fragment: String) -> String {
        guard fragment.contains("nsk-magic-tabs") else { return fragment }
        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_fragment_root__\">\(fragment)</div>",
            encoding: .utf8
        ),
              let root = document.at_css("#__nodeseek_fragment_root__") else {
            return fragment
        }

        let expanded = root.children
            .compactMap { expandedHTML(for: $0) }
            .joined()
        return expanded.isEmpty ? fragment : expanded
    }

    func expandedHTML(for node: XMLElement) -> String? {
        guard hasClass("nsk-magic-tabs", in: node) else {
            return node.toHTML
        }

        var sections: [String] = []
        var pendingTitleHTML: String?

        for child in node.children {
            if hasClass("nsk-magic-tab-title", in: child) {
                if let titleHTML = pendingTitleHTML {
                    sections.append(expandedMagicTabTitleHTML(titleHTML))
                }
                pendingTitleHTML = child.innerHTML ?? child.text
                continue
            }

            if hasClass("nsk-magic-tab-body", in: child) {
                if let titleHTML = pendingTitleHTML {
                    sections.append(expandedMagicTabTitleHTML(titleHTML))
                    pendingTitleHTML = nil
                }
                if let bodyHTML = child.innerHTML, bodyHTML.isEmpty == false {
                    sections.append("<div>\(simplifiedMagicTabBodyHTML(bodyHTML))</div>")
                }
                continue
            }

            if let titleHTML = pendingTitleHTML {
                sections.append(expandedMagicTabTitleHTML(titleHTML))
                pendingTitleHTML = nil
            }
            if let childHTML = child.toHTML {
                sections.append(childHTML)
            }
        }

        if let titleHTML = pendingTitleHTML {
            sections.append(expandedMagicTabTitleHTML(titleHTML))
        }

        return sections.joined(separator: "\n")
    }

    func expandedMagicTabTitleHTML(_ titleHTML: String) -> String {
        "<p><strong>\(titleHTML)</strong></p>"
    }

    func simplifiedMagicTabBodyHTML(_ bodyHTML: String) -> String {
        if let terminalText = xtermMagicTabText(from: bodyHTML) {
            return "<pre><code>\(escapedHTML(terminalText))</code></pre>"
        }

        let mayContainANSICode = bodyHTML.contains("language-ansi") || bodyHTML.contains("data-ansicode")
        guard mayContainANSICode else { return bodyHTML }
        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_magic_tab_body__\">\(bodyHTML)</div>",
            encoding: .utf8
        ),
              let root = document.at_css("#__nodeseek_magic_tab_body__") else {
            return bodyHTML
        }

        var blocks: [String] = []

        blocks.append(contentsOf: root.css("pre > code").compactMap { code -> String? in
            let isANSICode = hasClass("language-ansi", in: code) || (code.toHTML?.contains("data-ansicode") == true)
            guard isANSICode else { return nil }
            guard let rawText = code.text, rawText.isEmpty == false else { return nil }
            let normalizedText = stripANSICodes(from: rawText)
            guard normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            return "<pre><code>\(escapedHTML(normalizedText))</code></pre>"
        })

        for image in root.css("img") {
            if let imageHTML = image.toHTML {
                blocks.append(imageHTML)
            }
        }

        return blocks.isEmpty ? bodyHTML : blocks.joined(separator: "\n")
    }

    func isXtermMagicTabBodyHTML(_ bodyHTML: String) -> Bool {
        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_magic_tab_body__\">\(bodyHTML)</div>",
            encoding: .utf8
        ),
              let root = document.at_css("#__nodeseek_magic_tab_body__") else {
            let normalizedHTML = bodyHTML.lowercased()
            return normalizedHTML.contains("xterm-rows")
                || (normalizedHTML.contains("terminal-container") && normalizedHTML.contains("embedmode"))
        }

        if root.at_css(".xterm-rows") != nil {
            return true
        }

        return root.css(".terminal-container").contains { hasClass("embedMode", in: $0) }
    }

    /// xterm renders each terminal row as a separate div. Reading the rows directly avoids
    /// serializing its helper textarea and generated CSS while preserving every output line.
    func xtermMagicTabText(from bodyHTML: String) -> String? {
        xtermMagicTabCodeBlock(from: bodyHTML)?.text
    }

    /// NodeSeek 的 NodeQuality 报告会使用 xterm 输出 ANSI 颜色。原生端保留每段
    /// 字符串的颜色索引，而不是把整块终端降级为普通代码文本。
    func xtermMagicTabCodeBlock(from bodyHTML: String) -> RenderedCodeBlock? {
        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_magic_tab_body__\">\(bodyHTML)</div>",
            encoding: .utf8
        ), let root = document.at_css("#__nodeseek_magic_tab_body__"),
              let rows = root.at_css(".xterm-rows")
        else {
            return nil
        }

        var text = ""
        var runs: [RenderedCodeBlockRun] = []
        let rowNodes = Array(rows.xpath("./div"))
        for (rowIndex, row) in rowNodes.enumerated() {
            let spans = Array(row.xpath("./span"))
            if spans.isEmpty {
                appendTerminalText(
                    (row.text ?? "").replacingOccurrences(of: "\u{00A0}", with: " "),
                    state: .default,
                    to: &text,
                    runs: &runs
                )
            } else {
                for span in spans {
                    appendTerminalText(
                        (span.text ?? "").replacingOccurrences(of: "\u{00A0}", with: " "),
                        state: xtermStyle(for: span),
                        to: &text,
                        runs: &runs
                    )
                }
            }
            if rowIndex < rowNodes.count - 1 {
                text.append("\n")
            }
        }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return RenderedCodeBlock(text: text, style: .terminal, runs: runs)
    }

    private func ansiMagicTabCodeBlocks(from bodyHTML: String) -> [RenderedCodeBlock] {
        let normalizedHTML = bodyHTML.lowercased()
        guard normalizedHTML.contains("language-ansi") || normalizedHTML.contains("data-ansicode") else {
            return []
        }
        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_magic_tab_body__\">\(bodyHTML)</div>",
            encoding: .utf8
        ) else {
            return []
        }
        // 同一标签页可能包含多份 ANSI 报告（如 IPv4 + IPv6 各一份 pre），逐个收集。
        return document.css("pre > code").compactMap { codeNode in
            let isANSICode = hasClass("language-ansi", in: codeNode)
                || (codeNode.toHTML?.contains("data-ansicode") == true)
            guard isANSICode else { return nil }
            let rawText = codeText(from: codeNode).trimmingCharacters(in: .whitespacesAndNewlines)
            guard rawText.isEmpty == false else { return nil }
            // 先还原 data-ansicode 控制符占位 token 再解析 ANSI 颜色段。
            let terminal = terminalCodeBlock(
                fromANSIText: restoredANSIControlText(normalizedCodeText(rawText))
            )
            return terminal.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : terminal
        }
    }

    private struct TerminalStyle: Equatable {
        var foregroundColorIndex: Int?
        var backgroundColorIndex: Int?
        var isBold: Bool
        var isItalic: Bool
        var isUnderlined: Bool

        static let `default` = TerminalStyle(
            foregroundColorIndex: nil,
            backgroundColorIndex: nil,
            isBold: false,
            isItalic: false,
            isUnderlined: false
        )
    }

    private func xtermStyle(for node: XMLElement) -> TerminalStyle {
        let classes = (node["class"] ?? "").split(separator: " ").map(String.init)
        return TerminalStyle(
            foregroundColorIndex: xtermColorIndex(in: classes, prefix: "xterm-fg-"),
            backgroundColorIndex: xtermColorIndex(in: classes, prefix: "xterm-bg-"),
            isBold: classes.contains("xterm-bold"),
            isItalic: classes.contains("xterm-italic"),
            isUnderlined: classes.contains("xterm-underline")
        )
    }

    private func xtermColorIndex(in classes: [String], prefix: String) -> Int? {
        for className in classes where className.hasPrefix(prefix) {
            return Int(className.dropFirst(prefix.count))
        }
        return nil
    }

    private func appendTerminalText(
        _ value: String,
        state: TerminalStyle,
        to text: inout String,
        runs: inout [RenderedCodeBlockRun]
    ) {
        guard value.isEmpty == false else { return }
        let location = (text as NSString).length
        text.append(value)
        let length = (value as NSString).length
        guard state != .default else { return }
        runs.append(
            RenderedCodeBlockRun(
                location: location,
                length: length,
                foregroundColorIndex: state.foregroundColorIndex,
                backgroundColorIndex: state.backgroundColorIndex,
                isBold: state.isBold,
                isItalic: state.isItalic,
                isUnderlined: state.isUnderlined
            )
        )
    }

    /// ANSI 转义序列正则只需编译一次（原来每次调用都现场构造）。
    private static let ansiEscapeRegex = try! NSRegularExpression(
        pattern: "\u{001B}?\\[([0-9;]*)m",
        options: []
    )

    /// 解析 ANSI 转义文本为带颜色段的终端块。正文裸终端块与 magic tab 共用。
    func terminalCodeBlock(fromANSIText text: String) -> RenderedCodeBlock {
        let source = text as NSString
        let regex = Self.ansiEscapeRegex
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = regex.matches(in: text, range: fullRange)
        var terminalText = ""
        var runs: [RenderedCodeBlockRun] = []
        var state = TerminalStyle.default
        var currentLocation = 0

        for match in matches {
            let textRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            appendTerminalText(source.substring(with: textRange), state: state, to: &terminalText, runs: &runs)
            let codeString = source.substring(with: match.range(at: 1))
            applyANSICodes(codeString, to: &state)
            currentLocation = NSMaxRange(match.range)
        }
        let remainingRange = NSRange(location: currentLocation, length: fullRange.length - currentLocation)
        appendTerminalText(source.substring(with: remainingRange), state: state, to: &terminalText, runs: &runs)
        return RenderedCodeBlock(text: terminalText, style: .terminal, runs: runs)
    }

    private func applyANSICodes(_ value: String, to state: inout TerminalStyle) {
        let values = value.split(separator: ";", omittingEmptySubsequences: false).compactMap { Int($0) }
        let codes = values.isEmpty ? [0] : values
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                state = .default
            case 1:
                state.isBold = true
            case 3:
                state.isItalic = true
            case 4:
                state.isUnderlined = true
            case 22:
                state.isBold = false
            case 23:
                state.isItalic = false
            case 24:
                state.isUnderlined = false
            case 30...37:
                state.foregroundColorIndex = code - 30
            case 39:
                state.foregroundColorIndex = nil
            case 40...47:
                state.backgroundColorIndex = code - 40
            case 49:
                state.backgroundColorIndex = nil
            case 90...97:
                state.foregroundColorIndex = code - 90 + 8
            case 100...107:
                state.backgroundColorIndex = code - 100 + 8
            case 38, 48:
                guard index + 2 < codes.count, codes[index + 1] == 5 else { break }
                if code == 38 {
                    state.foregroundColorIndex = codes[index + 2]
                } else {
                    state.backgroundColorIndex = codes[index + 2]
                }
                index += 2
            default:
                break
            }
            index += 1
        }
    }

    func unsupportedContentHTML(reason: String) -> String {
        "<p class=\"\(Self.unsupportedContentClassName)\">\(escapedHTML(reason))</p>"
    }

    func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    func stripANSICodes(from text: String) -> String {
        // 占位 token 先还原成控制符再统一剥离，避免降级文本里残留私有区字符。
        let restoredText = restoredANSIControlText(text)
        let escapedText = restoredText.replacingOccurrences(of: "\u{001B}", with: "")
        let fullRange = NSRange(location: 0, length: (escapedText as NSString).length)
        return Self.ansiCodeRegex.stringByReplacingMatches(
            in: escapedText,
            options: [],
            range: fullRange,
            withTemplate: ""
        )
    }
}
