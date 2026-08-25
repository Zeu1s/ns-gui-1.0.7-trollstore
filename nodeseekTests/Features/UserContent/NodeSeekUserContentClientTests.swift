//
//  NodeSeekUserContentClientTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/11.
//

import Foundation
import Testing
@testable import nodeseek

@Suite(.serialized)
struct NodeSeekUserContentClientTests {
    @Test func accountUIDParsesSpaceProfileURL() throws {
        let account = AccountResponse(
            displayName: "mistj",
            isLoggedIn: true,
            profileURL: URL(string: "https://www.nodeseek.com/space/31037")!
        )

        #expect(account.nodeSeekUID == 31037)
    }

    @Test func loadsCollectionsFromJSONAPI() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "collections": [
                { "title": "如何把ChatGPT Plus订阅转换为API？", "post_id": 711961, "rank": 0 }
              ]
            }
            """
        )

        let records = try await client.loadCollections(page: 2, uid: 31037)

        #expect(MockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/statistics/list-collection?page=2")
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/space/31037")
        #expect(records == [
            UserCollectionRecord(title: "如何把ChatGPT Plus订阅转换为API？", postID: 711961, rank: 0)
        ])
    }

    @Test func loadsCommentsFromJSONAPI() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "comments": [
                {
                  "post_id": 715245,
                  "title": "已抽个GPT Plus",
                  "rank": 1,
                  "floor_id": 18,
                  "text": "让了让了 "
                }
              ]
            }
            """
        )

        let records = try await client.loadComments(uid: 31037, page: 4)

        #expect(MockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/content/list-comments?uid=31037&page=4")
        #expect(records == [
            UserCommentRecord(postID: 715245, title: "已抽个GPT Plus", rank: 1, floorID: 18, text: "让了让了")
        ])
    }

    @Test func loadsCommentsFromNestedPostAndReplyFields() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "comments": [
                {
                  "post": { "id": 715246, "title": "嵌套回复主题" },
                  "reply": {
                    "rank": 2,
                    "floor_id": 27,
                    "content": "![图](https://example.com/report.png)"
                  }
                }
              ]
            }
            """
        )

        let records = try await client.loadComments(uid: 31037, page: 1)

        #expect(records == [
            UserCommentRecord(
                postID: 715246,
                title: "嵌套回复主题",
                rank: 2,
                floorID: 27,
                text: "![图](https://example.com/report.png)"
            )
        ])
        #expect(records.first?.displayText == "用户发送图片")
    }

    @Test func loadsDiscussionsFromJSONAPI() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "discussions": [
                { "rank": 0, "title": "【开源】使用codex撸了一个nodeseek的iOS客户端", "post_id": 717963 }
              ]
            }
            """
        )

        let records = try await client.loadDiscussions(uid: 31037, page: 1)

        #expect(MockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/content/list-discussions?uid=31037&page=1")
        #expect(records == [
            UserDiscussionRecord(rank: 0, title: "【开源】使用codex撸了一个nodeseek的iOS客户端", postID: 717963)
        ])
    }
    @Test func loadsDiscussionsWithStatisticsFromWrappedEnvelope() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "data": {
                "discussions": [
                  { "rank": 0, "title": "测试贴", "post_id": 12345, "views": 843, "comments": 12 }
                ],
                "totalPage": 1
              }
            }
            """
        )

        let records = try await client.loadDiscussions(uid: 31037, page: 1)

        #expect(records == [
            UserDiscussionRecord(rank: 0, title: "测试贴", postID: 12345, viewCount: 843, replyCount: 12)
        ])
    }

    @Test func loadsDiscussionsWithAlternativeStatFieldNames() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "discussions": [
                { "rank": 0, "title": "备选字段", "post_id": 9001, "click": 120, "nComment": 7 }
              ]
            }
            """
        )

        let records = try await client.loadDiscussions(uid: 31037, page: 1)

        #expect(records == [
            UserDiscussionRecord(rank: 0, title: "备选字段", postID: 9001, viewCount: 120, replyCount: 7)
        ])
    }

    @Test func loadsDiscussionsWithNestedPostStatistics() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "discussions": [
                {
                  "post": {
                    "title": "嵌套统计主题帖",
                    "id": 9002,
                    "statistics": { "n_view": "4096", "n_comment": 28 }
                  }
                }
              ]
            }
            """
        )

        let records = try await client.loadDiscussions(uid: 31037, page: 1)

        #expect(records == [
            UserDiscussionRecord(rank: 0, title: "嵌套统计主题帖", postID: 9002, viewCount: 4096, replyCount: 28)
        ])
    }

    @Test func nestedStatisticsWinOverOuterPlaceholderValues() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "discussions": [
                {
                  "title": "真实统计优先", "post_id": 9010, "view_count": 0, "reply_count": 0,
                  "post": {
                    "statistics": { "viewCount": "1.2K", "replyCount": "36" }
                  }
                }
              ]
            }
            """
        )

        let records = try await client.loadDiscussions(uid: 31037, page: 1)

        #expect(records == [
            UserDiscussionRecord(rank: 0, title: "真实统计优先", postID: 9010, viewCount: 1200, replyCount: 36)
        ])
    }

    @Test func deeplyWrappedStatisticsWinOverAllPlaceholderValues() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "data": {
                "payload": {
                  "discussions": [
                    {
                      "title": "多层统计主题", "post_id": 9011, "views": 0, "comments": 0,
                      "post_data": {
                        "statistics": {
                          "metrics": { "view_count": "8,901", "reply_count": "47" }
                        }
                      }
                    }
                  ]
                }
              }
            }
            """
        )

        let records = try await client.loadDiscussions(uid: 31037, page: 1)

        #expect(records == [
            UserDiscussionRecord(rank: 0, title: "多层统计主题", postID: 9011, viewCount: 8901, replyCount: 47)
        ])
    }

    @Test func loadsDiscussionsWithNestedLatestReplyAndNodeMetadata() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "discussions": [
                {
                  "post": {
                    "id": 9012,
                    "title": "完整的主题帖元信息",
                    "viewNum": "8,888",
                    "replyNum": 19,
                    "node": { "nodeName": "日常" }
                  },
                  "lastReply": {
                    "createdAt": "昨天 18:20",
                    "user": { "member_name": "最后回复者", "member_id": 9527 }
                  }
                }
              ]
            }
            """
        )

        let records = try await client.loadDiscussions(uid: 31037, page: 1)

        #expect(records == [
            UserDiscussionRecord(
                rank: 0,
                title: "完整的主题帖元信息",
                postID: 9012,
                viewCount: 8888,
                replyCount: 19,
                lastActivityText: "昨天 18:20",
                lastReplyAuthorName: "最后回复者",
                lastReplyAuthorID: 9527,
                nodeName: "日常"
            )
        ])
    }
    @Test func loadsCollectionsWithStatistics() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "collections": [
                { "title": "收藏贴", "post_id": 700, "rank": 0, "view_count": 2000, "reply_count": 30 }
              ]
            }
            """
        )

        let records = try await client.loadCollections(page: 1, uid: 31037)

        #expect(records == [
            UserCollectionRecord(title: "收藏贴", postID: 700, rank: 0, viewCount: 2000, replyCount: 30)
        ])
    }

    @Test func loadsCollectionsWithNestedPostStatistics() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "collections": [
                {
                  "username": "收藏者",
                  "post": {
                    "title": "嵌套统计收藏贴",
                    "id": 701,
                    "statistics": {
                      "n_view": "2401",
                      "n_comment": 31
                    }
                  }
                }
              ]
            }
            """
        )

        let records = try await client.loadCollections(page: 1, uid: 31037)

        #expect(records == [
            UserCollectionRecord(title: "嵌套统计收藏贴", postID: 701, rank: 0, viewCount: 2401, replyCount: 31)
        ])
    }

    @Test func loadsCollectionsWithNestedAuthorProfile() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "collections": [
                {
                  "post": {
                    "id": 702,
                    "title": "带作者资料的收藏贴",
                    "member": {
                      "username": "真实作者",
                      "avatar_url": "/avatar/702.png"
                    }
                  }
                }
              ]
            }
            """
        )

        let records = try await client.loadCollections(page: 1, uid: 31037)

        #expect(records == [
            UserCollectionRecord(
                title: "带作者资料的收藏贴",
                postID: 702,
                rank: 0,
                authorName: "真实作者",
                avatarURL: URL(string: "https://www.nodeseek.com/avatar/702.png")
            )
        ])
    }
}

private func makeClient(responseBody: String) -> NodeSeekUserContentClient {
    MockURLProtocol.responseData = Data(responseBody.utf8)
    MockURLProtocol.lastRequest = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return NodeSeekUserContentClient(session: session)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
