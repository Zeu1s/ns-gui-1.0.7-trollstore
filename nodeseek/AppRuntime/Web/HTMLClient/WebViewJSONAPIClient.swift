//
//  WebViewJSONAPIClient.swift
//  nodeseek
//
//  Created by Codex on 2026/9/13.
//

import Foundation

struct WebViewJSONAPIResponse {
    let statusCode: Int?
    let body: String
    let json: [String: Any]?

    init(object: [String: Any]) {
        statusCode = (object["statusCode"] as? NSNumber)?.intValue ?? object["statusCode"] as? Int
        body = object["body"] as? String ?? ""
        json = object["json"] as? [String: Any]
    }
}

enum WebViewJSONAPIError: LocalizedError, Equatable {
    case httpStatus(Int)
    case unsuccessful(String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessful(let message):
            return message ?? "接口返回失败"
        case .invalidResponse:
            return "接口返回格式异常"
        }
    }
}

/// 通过隐藏 WebView 同源 fetch 调用站点 JSON API。
/// 用于 URLSession 请求特征被 Cloudflare 指纹封锁时的回退通道。
enum WebViewJSONAPIClient {
    static func fetch(
        apiPath: String,
        referer: URL,
        method: String = "GET",
        body: String? = nil,
        headers: [String: String]? = nil,
        timeoutInterval: TimeInterval = 20
    ) async throws -> WebViewJSONAPIResponse {
        let startedAt = Date()
        let object = try await withHiddenWebViewPageActionLoader(
            logMessage: "准备通过隐藏 WebView 请求站点 API: method=\(method), path=\(apiPath), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: referer,
                source: WebViewAPIFetchAutomationScript.source,
                arguments: [
                    "apiPath": apiPath,
                    "method": method,
                    "body": body ?? "",
                    "headers": headers ?? [:]
                ],
                timeoutInterval: timeoutInterval,
                actionName: "站点 API 请求"
            )
        }

        let response = WebViewJSONAPIResponse(object: object)
        AppLog.info(
            .webView,
            "WebView API 请求结束: method=\(method), path=\(apiPath), status=\(response.statusCode.map(String.init) ?? "nil"), bodyLength=\(response.body.count), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
        )
        return response
    }

    /// 拉取 JSON 并校验成功响应；配合 403/拦截 检测做回退。
    static func fetchDecodable<Response: Decodable>(
        _ type: Response.Type,
        apiPath: String,
        referer: URL,
        method: String = "GET",
        body: String? = nil,
        headers: [String: String]? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        timeoutInterval: TimeInterval = 20
    ) async throws -> Response {
        let response = try await fetch(
            apiPath: apiPath,
            referer: referer,
            method: method,
            body: body,
            headers: headers,
            timeoutInterval: timeoutInterval
        )
        guard let statusCode = response.statusCode, (200..<300).contains(statusCode) else {
            throw WebViewJSONAPIError.httpStatus(response.statusCode ?? 0)
        }
        guard let data = response.body.data(using: .utf8) else {
            throw WebViewJSONAPIError.invalidResponse
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            AppLog.error(.webView, "WebView API 响应解析失败: path=\(apiPath), error=\(error.localizedDescription), body=\(response.body.prefix(400))")
            throw error
        }
    }
}
