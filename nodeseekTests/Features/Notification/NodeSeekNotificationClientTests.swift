//
//  NodeSeekNotificationClientTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/6/8.
//

import Foundation
import Testing
@testable import nodeseek

@Suite(.serialized)
struct NodeSeekNotificationClientTests {
    @Test func rendersSystemMessageMarkdownLinksForNativeNavigation() throws {
        let rendered = NodeSeekPrivateMessageMarkdownRenderer.render(
            "您的[评论](https://www.nodeseek.com/post-856579-3#27)被用户[Grey](https://www.nodeseek.com/space/8257)投喂鸡腿"
        )

        #expect(rendered.hasLinks)
        #expect(rendered.attributedText.string == "您的评论被用户Grey投喂鸡腿")

        var links: [String] = []
        let range = NSRange(location: 0, length: rendered.attributedText.length)
        rendered.attributedText.enumerateAttribute(.link, in: range) { value, _, _ in
            if let url = value as? URL {
                links.append(url.absoluteString)
            }
        }
        #expect(links == [
            "https://www.nodeseek.com/post-856579-3#27",
            "https://www.nodeseek.com/space/8257"
        ])
    }

    @Test func keepsMarkdownImageSyntaxOutOfMessageLinkRendering() {
        let rendered = NodeSeekPrivateMessageMarkdownRenderer.render(
            "![截图](https://image.example.com/report.png)"
        )

        #expect(rendered.hasLinks == false)
        #expect(rendered.attributedText.string == "![截图](https://image.example.com/report.png)")
    }

    @Test func loadsAtMeNotificationsFromJSONAPI() async throws {
        let counter = CookiePrepareCounter()
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "data": [
                {
                  "id": 3056861,
                  "viewed": 0,
                  "comment_id": 10503771,
                  "floor_id": 11,
                  "created_at": "2026-06-06T03:50:41.000Z",
                  "commenter_id": 24060,
                  "title": "奥特曼咋还不重置啊，出了这么大封号乌龙事件",
                  "post_id": 763505,
                  "first_comment_id": 10501640,
                  "commenter_name": "kiya"
                }
              ]
            }
            """,
            counter: counter
        )

        let records = try await client.loadAtMe()

        #expect(counter.count == 1)
        #expect(MockNotificationURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/notification/at-me/list")
        #expect(MockNotificationURLProtocol.lastRequest?.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/notification#/atMe")
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.id == 3056861)
        #expect(record.isViewed == false)
        #expect(record.commentPage == 2)
        #expect(record.anchorID == "11")
        #expect(record.avatarURL.absoluteString == "https://www.nodeseek.com/avatar/24060.png")
        #expect(record.profileURL.absoluteString == "https://www.nodeseek.com/space/24060")
        #expect(record.postSummary.url.absoluteString == "https://www.nodeseek.com/post-763505-1")
    }

    @Test func readsReplyPreviewFromAlternativeContentFields() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "data": [
                {
                  "id": 3056862,
                  "viewed": 0,
                  "comment_id": 10503772,
                  "floor_id": 12,
                  "created_at": "2026-06-06T03:50:41.000Z",
                  "commenter_id": 24061,
                  "post_title": "带正文的通知",
                  "post_id": 763506,
                  "first_comment_id": 10501641,
                  "commenter_name": "kiya",
                  "reply_content": "<p>回复正文 <img src=\"https://example.com/report.png\"></p>"
                }
              ]
            }
            """
        )

        let records = try await client.loadAtMe()
        let record = try #require(records.first)

        #expect(record.content == "<p>回复正文 <img src=\"https://example.com/report.png\"></p>")
        #expect(UserCommentPreview.text(from: record.content ?? "") == "回复正文")
    }

    @Test func resolvesNotificationPreviewByCommentIDBeforeFloorFallback() {
        let record = NodeSeekNotificationRecord(
            id: 3056863,
            viewed: 0,
            commentID: 10503773,
            floorID: 12,
            createdAt: Date(timeIntervalSince1970: 1_000),
            commenterID: 24061,
            title: "通知标题",
            postID: 763507,
            firstCommentID: 10501642,
            commenterName: "kiya"
        )
        let detail = PostDetail(
            id: "763507",
            title: "通知标题",
            authorName: "作者",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "",
            comments: [
                Comment(
                    id: "10503772",
                    anchorID: "12",
                    authorName: "其他用户",
                    avatarURL: nil,
                    floorText: "12 楼",
                    createdAtText: nil,
                    contentHTML: "<p>不应匹配</p>"
                ),
                Comment(
                    id: "comment-10503773",
                    anchorID: "11",
                    authorName: "kiya",
                    avatarURL: nil,
                    floorText: "11 楼",
                    createdAtText: nil,
                    contentHTML: "<p>目标回复</p>"
                )
            ]
        )

        #expect(NodeSeekNotificationContentResolver.content(in: detail, for: record) == "<p>目标回复</p>")
    }

    @Test func derivesCommentPageFromActualSecondPageFloor() {
        let secondPage = PostDetail(
            id: "763508",
            title: "通知标题",
            authorName: "作者",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "",
            comments: [
                Comment(
                    id: "10503774",
                    anchorID: "21",
                    authorName: "kiya",
                    avatarURL: nil,
                    floorText: "21 楼",
                    createdAtText: nil,
                    contentHTML: "<p>目标回复</p>"
                ),
                Comment(
                    id: "10503775",
                    anchorID: "40",
                    authorName: "其他用户",
                    avatarURL: nil,
                    floorText: "40 楼",
                    createdAtText: nil,
                    contentHTML: "<p>另一条回复</p>"
                )
            ]
        )

        let commentsPerPage = try #require(
            NodeSeekNotificationContentResolver.commentsPerPage(inSecondPage: secondPage)
        )
        #expect(commentsPerPage == 20)
        #expect(NodeSeekNotificationContentResolver.page(for: 12, commentsPerPage: commentsPerPage) == 1)
        #expect(NodeSeekNotificationContentResolver.page(for: 21, commentsPerPage: commentsPerPage) == 2)
        #expect(NodeSeekNotificationContentResolver.page(for: 99, commentsPerPage: commentsPerPage) == 5)
    }

    @Test func notificationReplyUsesThePageWhereContentWasResolved() {
        let record = NodeSeekNotificationRecord(
            id: 3056865,
            viewed: 0,
            commentID: 10503775,
            floorID: 21,
            createdAt: Date(timeIntervalSince1970: 1_000),
            commenterID: 24061,
            title: "通知标题",
            postID: 763509,
            firstCommentID: 10501644,
            resolvedCommentPage: 2,
            commenterName: "kiya"
        )

        #expect(record.commentPage == 3)
        #expect(record.targetCommentPage == 2)
    }

    @Test func loadsUnreadCount() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "unreadCount": {
                "message": 2,
                "atMe": 3,
                "reply": 4,
                "all": 9
              }
            }
            """
        )

        let count = try await client.loadUnreadCount()

        #expect(MockNotificationURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/notification/unread-count")
        #expect(count.message == 2)
        #expect(count.atMe == 3)
        #expect(count.reply == 4)
        #expect(count.all == 9)
    }

    @Test func writesNotificationAPIRequestLogs() async throws {
        try await withTemporaryFileLogging {
            let client = makeClient(
                responseBody: """
                {
                  "success": true,
                  "unreadCount": {
                    "message": 2,
                    "atMe": 3,
                    "reply": 4,
                    "all": 9
                  }
                }
                """
            )

            _ = try await client.loadUnreadCount()
            AppLog.flushFileLogsForTesting()

            let content = try AppLog.fileLogContent()
            #expect(content.contains("[info] [Service] ["))
            #expect(content.contains("通知接口请求开始 method=GET, url=https://www.nodeseek.com/api/notification/unread-count"))
            #expect(content.contains("通知接口响应成功 method=GET, url=https://www.nodeseek.com/api/notification/unread-count"))
            #expect(content.contains("status=200"))
            #expect(content.contains("responseType=UnreadCountResponse"))
        }
    }

    @Test func marksAtMeNotificationViewedWithNotificationIDBody() async throws {
        let submitter = SpyNotificationMarkViewedSubmitter()
        let client = makeClient(responseBody: #"{"success":true}"#, markViewedSubmitter: submitter)

        try await client.markViewed(ids: [0, 3056861], tab: .atMe)

        let submissions = await submitter.submissions()
        let submission = try #require(submissions.first)
        #expect(submission.request.apiPath == "/api/notification/at-me/markViewed")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/notification#/atMe")
        let bodyJSON = try #require(submission.request.bodyJSON)
        let bodyData = Data(bodyJSON.utf8)
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: [Int]])
        #expect(json["atMe"] == [3056861])
    }

    @Test func skipsMarkViewedWhenNotificationIDsAreInvalid() async throws {
        let submitter = SpyNotificationMarkViewedSubmitter()
        let client = makeClient(responseBody: #"{"success":true}"#, markViewedSubmitter: submitter)

        try await client.markViewed(ids: [0, -1], tab: .atMe)

        let submissions = await submitter.submissions()
        #expect(submissions.isEmpty)
    }

    @Test func marksAllRepliesViewed() async throws {
        let submitter = SpyNotificationMarkViewedSubmitter()
        let client = makeClient(responseBody: #"{"success":true}"#, markViewedSubmitter: submitter)

        try await client.markAllViewed(tab: .reply)

        let submissions = await submitter.submissions()
        let submission = try #require(submissions.first)
        #expect(submission.request.apiPath == "/api/notification/reply-to-me/markViewed?all=true")
        #expect(submission.request.bodyJSON == nil)
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/notification#/reply")
    }

    @Test func loadsMessageConversationsAndResolvesParticipant() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "msgArray": [
                {
                  "receiver_id": 31037,
                  "sender_id": 24060,
                  "max_id": 920,
                  "content": "hello",
                  "created_at": "2026-06-05T12:59:10.000Z",
                  "viewed": 0,
                  "sender_name": "kiya",
                  "receiver_name": "mistj"
                }
              ]
            }
            """
        )

        let records = try await client.loadMessageConversations()

        #expect(MockNotificationURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/notification/message/list")
        let record = try #require(records.first)
        #expect(record.participantID(currentUserID: 31037) == 24060)
        #expect(record.participantName(currentUserID: 31037) == "kiya")
        #expect(record.conversationWebURL(currentUserID: 31037).absoluteString == "https://www.nodeseek.com/notification#/message?mode=talk&to=24060")
    }

    @Test func loadsNestedMessageListAndIgnoresMalformedLegacyRecord() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "data": {
                "message_list": [
                  {
                    "receiver_id": "31037",
                    "sender_id": "24060",
                    "max_id": "920",
                    "content": null,
                    "created_at": "2026-06-05T12:59:10.000Z",
                    "viewed": false,
                    "sender_name": "kiya",
                    "receiver_name": "mistj"
                  },
                  42
                ]
              }
            }
            """
        )

        let records = try await client.loadMessageConversations()

        #expect(records.count == 1)
        #expect(records.first?.receiverID == 31037)
        #expect(records.first?.content == "")
        #expect(records.first?.isViewed == false)
    }

    @Test func keepsOnlyLatestMessageForEachConversation() {
        let older = NodeSeekMessageConversationRecord(
            receiverID: 31037,
            senderID: 24060,
            maxID: 920,
            content: "较早消息",
            createdAt: Date(timeIntervalSince1970: 1_000),
            viewed: 0,
            senderName: "kiya",
            receiverName: "mistj"
        )
        let latestOutgoing = NodeSeekMessageConversationRecord(
            receiverID: 24060,
            senderID: 31037,
            maxID: 921,
            content: "最新消息",
            createdAt: Date(timeIntervalSince1970: 2_000),
            viewed: 0,
            senderName: "mistj",
            receiverName: "kiya"
        )

        let conversations = NodeSeekMessageConversationRecord.latestConversations(
            from: [older, latestOutgoing],
            currentUserID: 31037
        )

        #expect(conversations.count == 1)
        #expect(conversations.first?.maxID == 921)
        #expect(conversations.first?.content == "最新消息")
        #expect(conversations.first?.isViewed == true)
        #expect(conversations.first?.participantName(currentUserID: 31037) == "kiya")
    }
}

private func makeClient(
    responseBody: String,
    counter: CookiePrepareCounter = CookiePrepareCounter(),
    markViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting = SpyNotificationMarkViewedSubmitter()
) -> NodeSeekNotificationClient {
    MockNotificationURLProtocol.responseData = Data(responseBody.utf8)
    MockNotificationURLProtocol.lastRequest = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockNotificationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return NodeSeekNotificationClient(
        session: session,
        cookiePreparer: {
            counter.increment()
        },
        markViewedSubmitter: markViewedSubmitter
    )
}

private func withTemporaryFileLogging(_ body: () async throws -> Void) async throws {
    try await FileLoggingTestGate.shared.withExclusiveAccess {
        let previousFileLoggingEnabled = NodeSeekDebugConfig.enableFileLogging
        let previousAvatarLoggingEnabled = NodeSeekDebugConfig.enableAvatarImageLogs
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            NodeSeekDebugConfig.enableFileLogging = previousFileLoggingEnabled
            NodeSeekDebugConfig.enableAvatarImageLogs = previousAvatarLoggingEnabled
            AppLog.setFileLogDirectoryForTesting(nil)
        }

        AppLog.setFileLogDirectoryForTesting(directory)
        NodeSeekDebugConfig.enableFileLogging = true
        try await body()
    }
}

private final class CookiePrepareCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private actor SpyNotificationMarkViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting {
    struct Submission {
        let request: NodeSeekNotificationMarkViewedRequest
        let referer: URL
    }

    private var values: [Submission] = []

    func submit(_ request: NodeSeekNotificationMarkViewedRequest, referer: URL) async throws {
        values.append(Submission(request: request, referer: referer))
    }

    func submissions() -> [Submission] {
        values
    }
}

private final class MockNotificationURLProtocol: URLProtocol, @unchecked Sendable {
    static var responseData = Data()
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
