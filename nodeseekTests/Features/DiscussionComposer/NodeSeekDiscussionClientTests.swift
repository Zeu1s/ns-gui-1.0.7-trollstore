//
//  NodeSeekDiscussionClientTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@Suite(.serialized)
struct NodeSeekDiscussionClientTests {
    @Test func submitsNativeDiscussionWithExpectedPayload() async throws {
        MockDiscussionURLProtocol.responseData = Data(
            #"{"success":true,"redirect":"/post-810001-1","redirectHash":"0"}"#.utf8
        )
        MockDiscussionURLProtocol.lastRequest = nil
        let client = NodeSeekDiscussionClient(
            session: makeDiscussionSession(),
            cookiePreparer: {}
        )

        let submission = try await client.submit(
            NodeSeekDiscussionDraft(
                title: "原生发帖",
                content: "正文内容",
                category: "tech",
                rank: 0
            )
        )

        let request = try #require(MockDiscussionURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://www.nodeseek.com/api/content/new-discussion")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/new-discussion")
        #expect(request.value(forHTTPHeaderField: "csrf-token")?.count == 16)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["title"] as? String == "原生发帖")
        #expect(json["content"] as? String == "正文内容")
        #expect(json["category"] as? String == "tech")
        #expect(json["rank"] as? Int == 0)
        #expect(json["mode"] as? String == "new-discussion")
        #expect(submission.redirect == "/post-810001-1")
        #expect(submission.redirectHash == "0")
    }
}

private func makeDiscussionSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockDiscussionURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MockDiscussionURLProtocol: URLProtocol, @unchecked Sendable {
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
