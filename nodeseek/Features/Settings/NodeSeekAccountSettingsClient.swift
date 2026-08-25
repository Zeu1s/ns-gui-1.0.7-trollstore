//
//  NodeSeekAccountSettingsClient.swift
//  nodeseek
//

import Foundation

nonisolated struct NodeSeekAccountEditableProfile: Equatable, Sendable {
    let bio: String
    let signature: String
    let readme: String
}

protocol NodeSeekAccountSettingsManaging {
    func loadProfile(userID: Int) async throws -> NodeSeekAccountEditableProfile
    func updateProfile(_ profile: NodeSeekAccountEditableProfile) async throws
    func uploadAvatarPNG(_ data: Data) async throws
}

enum NodeSeekAccountSettingsClientError: LocalizedError, Equatable {
    case httpStatus(Int)
    case unsuccessfulResponse(String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessfulResponse(let message):
            return message ?? "账号设置接口返回失败"
        case .invalidResponse:
            return "账号设置接口返回格式异常"
        }
    }
}

final class NodeSeekAccountSettingsClient: NodeSeekAccountSettingsManaging {
    private let session: URLSession
    private let baseURL: URL
    private let cookiePreparer: @Sendable () async -> Void

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        cookiePreparer: @escaping @Sendable () async -> Void = {
            await NodeSeekCookieSession().prepareHTTPLoad()
        }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookiePreparer = cookiePreparer
    }

    func loadProfile(userID: Int) async throws -> NodeSeekAccountEditableProfile {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/account/getInfo/\(userID)"
        components?.queryItems = [
            URLQueryItem(name: "readme", value: "1"),
            URLQueryItem(name: "signature", value: "1"),
            URLQueryItem(name: "phone", value: "1")
        ]
        let url = components?.url ?? baseURL.appendingPathComponent("/api/account/getInfo/\(userID)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: settingsURL)

        let root = try await performJSONRequest(request)
        guard let detail = root["detail"] as? [String: Any] else {
            throw NodeSeekAccountSettingsClientError.invalidResponse
        }
        return NodeSeekAccountEditableProfile(
            bio: Self.string(detail["bio"]),
            signature: Self.string(detail["signature_markdown"]),
            readme: Self.string(detail["readme"])
        )
    }

    func updateProfile(_ profile: NodeSeekAccountEditableProfile) async throws {
        let body: [String: String] = [
            "bio": profile.bio,
            "signature": profile.signature,
            "readme": profile.readme
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: endpoint(path: "/api/account/introduction"))
        request.httpMethod = "POST"
        request.httpBody = data
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: settingsURL)
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        _ = try await performJSONRequest(request)
    }

    func uploadAvatarPNG(_ data: Data) async throws {
        let boundary = "NodeSeekAvatarBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint(path: "/api/avatar/upload"))
        request.httpMethod = "POST"
        request.httpBody = Self.multipartBody(data: data, boundary: boundary)
        WebRequestFingerprint.applyImageHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(settingsURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("simple-token", forHTTPHeaderField: "x-csrf-challenge")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        _ = try await performJSONRequest(request)
    }

    private var settingsURL: URL {
        baseURL.appendingPathComponent("setting")
    }

    private func endpoint(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        return components?.url ?? baseURL.appendingPathComponent(path)
    }

    private func performJSONRequest(_ request: URLRequest) async throws -> [String: Any] {
        await cookiePreparer()
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw NodeSeekAccountSettingsClientError.httpStatus(httpResponse.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NodeSeekAccountSettingsClientError.invalidResponse
        }
        guard Self.bool(root["success"]) != false else {
            throw NodeSeekAccountSettingsClientError.unsuccessfulResponse(Self.string(root["message"]))
        }
        return root
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func string(_ value: Any?) -> String {
        guard let value = value as? String else { return "" }
        return value == "null" ? "" : value
    }

    private static func multipartBody(data: Data, boundary: String) -> Data {
        var body = Data()
        func append(_ value: String) {
            body.append(Data(value.utf8))
        }

        for (name, value) in [("token", "123456798"), ("name", "avatar")] {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"img\"; filename=\"avatar.png\"\r\n")
        append("Content-Type: image/png\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
