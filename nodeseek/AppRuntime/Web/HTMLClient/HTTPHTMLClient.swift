//
//  HTTPHTMLClient.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct HTTPHTMLClient: HTMLClient {
    private let session: URLSession

    /// 不用 URLSession.shared：它的请求超时是 60 秒，被 Cloudflare 挂住时要拖满
    /// 一分钟才进入 WebView 回退，这段时间界面只能转圈。取值对齐项目内其它网络配置。
    /// 必须是静态成员——makeClient() 每次调用都会新建一个 HTTPHTMLClient。
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    init(session: URLSession = HTTPHTMLClient.defaultSession) {
        self.session = session
    }

    func get(_ url: URL) async throws -> HTMLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyDefaultHeaders(to: &request)
        return try await perform(request)
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyDefaultHeaders(to: &request)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formFields
            .map { key, value in "\(Self.urlEncode(key))=\(Self.urlEncode(value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> HTMLResponse {
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let headers = httpResponse?.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        } ?? [:]
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)

        return HTMLResponse(
            statusCode: httpResponse?.statusCode ?? 0,
            headers: headers,
            finalURL: httpResponse?.url ?? request.url!,
            html: html
        )
    }

    private func applyDefaultHeaders(to request: inout URLRequest) {
        WebRequestFingerprint.applyHTMLHeaders(to: &request)
    }

    private static func urlEncode(_ value: String) -> String {
        FormURLEncoder.encode(value)
    }
}
