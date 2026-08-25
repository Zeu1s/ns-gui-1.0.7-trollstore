//
//  HTTPAutoCheckInAutomatorTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct HTTPAutoCheckInAutomatorTests {
    @Test func loadsBoardStateWithoutWebView() async throws {
        MockCheckInURLProtocol.responseData = Data(
            #"{"record":[{"isCurrent":true}],"memberList":[]}"#.utf8
        )
        MockCheckInURLProtocol.lastRequest = nil
        let automator = HTTPAutoCheckInAutomator(session: makeCheckInSession(), cookiePreparer: {})

        let boardState = try await automator.fetchBoardState(runID: "test")

        #expect(MockCheckInURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/attendance/board?page=1")
        #expect(MockCheckInURLProtocol.lastRequest?.httpMethod == "GET")
        #expect(boardState.ok)
        #expect(boardState.isLoggedIn)
        #expect(boardState.isCheckedIn)
        #expect(boardState.detectionSource == "board_current_record")
    }

    @Test func submitsCheckInWithoutWebView() async throws {
        MockCheckInURLProtocol.responseData = Data(#"{"success":true,"message":"签到成功","current":5}"#.utf8)
        MockCheckInURLProtocol.lastRequest = nil
        let automator = HTTPAutoCheckInAutomator(session: makeCheckInSession(), cookiePreparer: {})

        let result = try await automator.submit(mode: .fixedChickenLeg, runID: "test")

        #expect(MockCheckInURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/attendance?random=false")
        #expect(MockCheckInURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(result.ok)
        #expect(result.success == true)
        #expect(result.current == 5)
    }
}

private func makeCheckInSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockCheckInURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MockCheckInURLProtocol: URLProtocol, @unchecked Sendable {
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
