import Foundation
import Testing
@testable import nodeseek

struct CommentReplyReferenceResolverTests {
    /// 叠楼：站点把"引用某楼"写成正文开头的 blockquote，多级引用就是并列的多个块，
    /// 每块第一行是 `@某人 #楼层 发布于…，编辑于…`。这些原文必须原样留在正文里，
    /// 不能再压成一张只装得下第一级的纯文本卡片。
    @Test func leadingQuoteChainStaysInlineInsteadOfCollapsingIntoACard() {
        let first = makeComment(id: "1", author: "kkkku", floor: "#1", html: "<p>原始内容</p>")
        let second = makeComment(id: "2", author: "keyzal", floor: "#2", html: "<p>要是不限制速就留 tyyun 了</p>")
        let fourth = makeComment(
            id: "4",
            author: "kkkku",
            floor: "#4",
            html: "<blockquote><a href=\"#2\">@keyzal #2</a> 发布于今天<br><a href=\"#1\">@kkkku #1</a> 要是不限制速就留 tyyun 了</blockquote><br><p>我是搞了个 newapi，小站自用</p>"
        )

        #expect(CommentReplyReferenceResolver.containsQuoteBlock(in: fourth.contentHTML))
        #expect(
            CommentReplyReferenceResolver.reference(for: fourth, among: [first, second, fourth]) == nil
        )
        #expect(
            CommentReplyReferenceResolver.contentHTMLRemovingLeadingReference(
                from: fourth.contentHTML,
                reference: nil
            ) == fourth.contentHTML
        )
    }

    @Test func stackedSiblingQuotesAreDetected() {
        let html = """
        <blockquote><p><a href="/member?t=a">@a</a> <a href="/post-938518-1#2">#2</a> 发布于2026/9/20 14:50:11</p><p>不行，也会被封机器</p></blockquote>
        <blockquote><p><a href="/member?t=b">@b</a> <a href="/post-938518-1#3">#3</a> 发布于2026/9/20 14:50:14，编辑于2026/9/20 14:50:35</p><p>可以 但不保证不封</p></blockquote>
        <p>那看来是不能直接搭了</p>
        """

        #expect(CommentReplyReferenceResolver.containsQuoteBlock(in: html))
    }

    /// 真机截图里那条 #23：正文先是一段 `@某人 #楼层` 的跳转段落，引用块排在它后面。
    /// 判定只看开头会漏掉这条，于是仍然走卡片、摘要被挤成一行裁掉。
    @Test func quoteBlockAfterALeadingMentionParagraphIsStillDetected() {
        let html = """
        <p><a href="/member?t=walker">@Walker-</a> <a href="/post-1-1#20">#20</a></p>
        <blockquote><p><a href="/member?t=walker">@Walker-</a> <a href="/post-1-1#20">#20</a> 发布于2026/9/21 11:02:07</p><p>clash 更新订阅就可以用了</p></blockquote>
        """

        #expect(CommentReplyReferenceResolver.containsQuoteBlock(in: html))
    }

    /// 只带一个跳转链接、没有引用原文的回复仍然走卡片，这条路径上没有任何内容会被丢掉。
    @Test func bareLeadingJumpLinkStillProducesCardAndIsRemoved() throws {
        let first = makeComment(id: "1", author: "kkkku", floor: "#1", html: "<p>原始内容</p>")
        let second = makeComment(
            id: "2",
            author: "keyzal",
            floor: "#2",
            html: "<a href=\"#1\">@kkkku #1</a><br>要是不限制速就留 tyyun 了"
        )

        let reference = try #require(
            CommentReplyReferenceResolver.reference(for: second, among: [first, second])
        )
        #expect(reference.displayText == "@kkkku  #1\n原始内容")
        #expect(
            CommentReplyReferenceResolver.contentHTMLRemovingLeadingReference(
                from: second.contentHTML,
                reference: reference
            ) == "要是不限制速就留 tyyun 了"
        )
    }

    @Test func plainMentionIsNotTreatedAsAReplyReference() {
        let first = makeComment(id: "1", author: "kkkku", floor: "#1", html: "<p>原始内容</p>")
        let second = makeComment(id: "2", author: "keyzal", floor: "#2", html: "<p>@kkkku 你看看这个</p>")

        #expect(CommentReplyReferenceResolver.reference(for: second, among: [first, second]) == nil)
    }

    private func makeComment(id: String, author: String, floor: String, html: String) -> Comment {
        Comment(
            id: id,
            anchorID: String(floor.dropFirst()),
            authorName: author,
            avatarURL: nil,
            floorText: floor,
            createdAtText: nil,
            contentHTML: html
        )
    }
}
