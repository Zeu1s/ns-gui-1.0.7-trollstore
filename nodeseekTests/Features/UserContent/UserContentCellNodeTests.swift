//
//  UserContentCellNodeTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/11.
//

import Testing
import UIKit
@testable import nodeseek

struct UserContentCellNodeTests {
    @Test func titleTypographyUsesSameBaselineAsPostList() throws {
        let text = UserContentText.title("标题")
        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)

        #expect(font.pointSize == PostListCellStyle.Typography.titleFont.pointSize)
        #expect(font.pointSize == AppTextSizeSettings.adjustedPointSize(basePointSize: 17))
    }

    @Test func commentPreviewKeepsTextAndHidesEmbeddedImages() {
        let preview = UserCommentPreview.text(
            from: "图示 ![速度图](https://example.com/report.png) <img src=\"https://example.com/chart.png\">"
        )

        #expect(preview == "图示")
    }

    @Test func commentPreviewUsesImageLabelWhenNoTextRemains() {
        let preview = UserCommentPreview.text(from: "![速度图](https://example.com/report.png)")

        #expect(preview == "用户发送图片")
    }

    @Test func commentPreviewKeepsTextFromHTMLAndHidesImages() {
        let preview = UserCommentPreview.text(
            from: "<p>测试回复&nbsp;<img src=\"https://example.com/report.png\"></p>"
        )

        #expect(preview == "测试回复")
    }

    @Test func commentPreviewTextUsesHighlightBackground() throws {
        let text = UserContentText.commentPreview("回复内容")
        let backgroundColor = try #require(text.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? UIColor)

        #expect(backgroundColor != .clear)
    }
}
