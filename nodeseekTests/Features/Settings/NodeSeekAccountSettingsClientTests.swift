//
//  NodeSeekAccountSettingsClientTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@Suite(.serialized)
struct NodeSeekAccountSettingsClientTests {
    @Test func loadsEditableProfileWithNodeSeekFields() async throws {
        let client = makeAccountSettingsClient(
            response: """
            {
              "success": true,
              "detail": {
                "bio": "No one but you",
                "signature_markdown": "[私信](https://www.nodeseek.com/notification#/message)",
                "readme": "# Readme"
              }
            }
            """
        )

        let profile = try await client.loadProfile(userID: 31037)

        #expect(profile == NodeSeekAccountEditableProfile(
            bio: "No one but you",
            signature: "[私信](https://www.nodeseek.com/notification#/message)",
            readme: "# Readme"
        ))
        #expect(AccountSettingsMockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/account/getInfo/31037?readme=1&signature=1&phone=1")
        #expect(AccountSettingsMockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/setting")
    }

    @Test func updatesEditableProfileThroughVerifiedIntroductionEndpoint() async throws {
        let client = makeAccountSettingsClient(response: #"{"success":true}"#)
        let profile = NodeSeekAccountEditableProfile(bio: "Bio", signature: "签名", readme: "Readme")

        try await client.updateProfile(profile)

        let request = try #require(AccountSettingsMockURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://www.nodeseek.com/api/account/introduction")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["bio": "Bio", "signature": "签名", "readme": "Readme"])
    }

    @Test func uploadsAvatarUsingVerifiedMultipartFields() async throws {
        let client = makeAccountSettingsClient(response: #"{"success":true}"#)

        try await client.uploadAvatarPNG(Data([0x89, 0x50, 0x4E, 0x47]))

        let request = try #require(AccountSettingsMockURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://www.nodeseek.com/api/avatar/upload")
        #expect(request.value(forHTTPHeaderField: "x-csrf-challenge") == "simple-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("name=\"token\""))
        #expect(body.contains("name=\"name\""))
        #expect(body.contains("name=\"img\"; filename=\"avatar.png\""))
    }
}

private func makeAccountSettingsClient(response: String) -> NodeSeekAccountSettingsClient {
    AccountSettingsMockURLProtocol.responseData = Data(response.utf8)
    AccountSettingsMockURLProtocol.lastRequest = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AccountSettingsMockURLProtocol.self]
    return NodeSeekAccountSettingsClient(
        session: URLSession(configuration: configuration),
        cookiePreparer: {}
    )
}

private final class AccountSettingsMockURLProtocol: URLProtocol, @unchecked Sendable {
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
