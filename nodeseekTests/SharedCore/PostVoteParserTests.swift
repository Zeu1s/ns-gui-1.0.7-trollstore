//
//  PostVoteParserTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct PostVoteParserTests {
    @Test func parsesSingleChoiceVoteFromPostDetail() throws {
        let html = """
        <html>
          <head><meta property="og:title" content="投票测试"></head>
          <body>
            <section class="nsk-post">
              <article class="content-item">
                <a class="author-name">tester</a>
                <div class="post-content">正文</div>
              </article>
            </section>
            <div id="vote-editor-mount" data-vote-id="42">
              <h3 class="vote-title">你会选择哪个方案？</h3>
              <label><input type="radio" value="a">方案 A 12 票</label>
              <label><input type="radio" value="b" checked>方案 B 8 票</label>
              <button>投票</button>
              <span>共 20 票</span>
            </div>
          </body>
        </html>
        """

        let detail = try KannaNodeSeekParser().parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-42-1")!
        )

        let vote = try #require(detail.vote)
        #expect(vote.id == "42")
        #expect(vote.title == "你会选择哪个方案？")
        #expect(vote.allowsMultipleSelection == false)
        #expect(vote.totalVoteCount == 20)
        #expect(vote.canSubmit == true)
        #expect(vote.options.map(\.id) == ["a", "b"])
        #expect(vote.options.map(\.voteCount) == [12, 8])
        #expect(vote.options.map(\.isSelected) == [false, true])
    }
}
