import Foundation
import Testing
@testable import nodeseek

struct CommentReplyReferenceResolverTests {
    @Test func displayHTMLKeepsOnlyReferenceCardAndNewReplyContent() throws {
        let first = makeComment(id: "1", author: "kkkku", floor: "#1", html: "<p>原始内容</p>")
        let second = makeComment(
            id: "2",
            author: "keyzal",
            floor: "#2",
            html: "<a href=\"#1\">@kkkku #1</a><br>要是不限制速就留 tyyun 了"
        )
        let fourth = makeComment(
            id: "4",
            author: "kkkku",
            floor: "#4",
            html: "<blockquote><a href=\"#2\">@keyzal #2</a> 发布于今天<br><a href=\"#1\">@kkkku #1</a> 要是不限制速就留 tyyun 了</blockquote><br><p>我是搞了个 newapi，小站自用</p>"
        )

        let reference = try #require(CommentReplyReferenceResolver.reference(for: fourth, among: [first, second, fourth]))
        let displayHTML = CommentReplyReferenceResolver.contentHTMLRemovingLeadingReference(
            from: fourth.contentHTML,
            reference: reference
        )

        #expect(reference.flatDisplayText == "回复 @keyzal · #2：要是不限制速就留 tyyun 了")
        #expect(reference.displayText == "@keyzal  #2\n要是不限制速就留 tyyun 了")
        #expect(displayHTML == "<p>我是搞了个 newapi，小站自用</p>")
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
