//
//  WebViewJSONAPIClient.swift
//  nodeseek
//
//  Created by Codex on 2026/9/13.
//

import CryptoKit
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

/// 站点接口的 x-dynamic-sign 计算。算法与站内前端一致：
/// SHA-1( METHOD + "\n\n" + 绝对URL + "\n\n" + userAgent + "\n\n" + body )，小写十六进制。
/// 之所以能在 Swift 侧算：隐藏 WebView 的 customUserAgent 就是
/// WebRequestFingerprint.userAgent，页面里 navigator.userAgent 取到同一个值；
/// apiPath 传的又已是绝对 URL，new URL(path, location.href) 不会改变它。
enum WebViewAPIDynamicSign {
    static func header(method: String, absoluteURL: String, body: String) -> String {
        let payload = [method, absoluteURL, WebRequestFingerprint.userAgent, body]
            .joined(separator: "\n\n")
        return Insecure.SHA1.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Csrf-Token 由前端自造 8 字节十六进制，服务端只查有无、不校验来源。
    static func csrfToken() -> String {
        (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

/// 通过隐藏 WebView 同源 fetch 调用站点 JSON API。
/// 用于 URLSession 请求特征被 Cloudflare 指纹封锁时的回退通道。
enum WebViewJSONAPIClient {
    /// 站点 429 后的冷却期：期间同源 fetch 直接按限流失败，不再轰炸。
    private static let rateLimitCooldown: TimeInterval = 30
    private static let cooldownLock = NSLock()
    private static var cooldownUntil: Date?

    private static func checkRateLimitCooldown() -> Bool {
        cooldownLock.lock()
        defer { cooldownLock.unlock() }
        guard let until = cooldownUntil else { return true }
        return Date() >= until
    }

    private static func triggerRateLimitCooldown() {
        cooldownLock.lock()
        defer { cooldownLock.unlock() }
        cooldownUntil = Date().addingTimeInterval(rateLimitCooldown)
        AppLog.warning(.webView, "站点 API 限流(429)，WebView 同源 fetch 进入 \(Int(rateLimitCooldown))s 冷却")
    }

    static func fetch(
        apiPath: String,
        referer: URL,
        method: String = "GET",
        body: String? = nil,
        headers: [String: String]? = nil,
        timeoutInterval: TimeInterval = 20,
        requireCleanPage: Bool = true,
        signed: Bool = false
    ) async throws -> WebViewJSONAPIResponse {
        guard checkRateLimitCooldown() else {
            throw WebViewJSONAPIError.httpStatus(429)
        }
        var requestHeaders = headers ?? [:]
        if signed {
            let bodyText = body ?? ""
            requestHeaders["x-dynamic-sign"] = WebViewAPIDynamicSign.header(
                method: method,
                absoluteURL: apiPath,
                body: bodyText
            )
            if method.uppercased() != "GET" {
                requestHeaders["Csrf-Token"] = WebViewAPIDynamicSign.csrfToken()
            }
        }
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
                    "headers": requestHeaders
                ],
                timeoutInterval: timeoutInterval,
                actionName: "站点 API 请求",
                requireCleanPage: requireCleanPage
            )
        }

        let response = WebViewJSONAPIResponse(object: object)
        if response.statusCode == 429 {
            triggerRateLimitCooldown()
        }
        AppLog.info(
            .webView,
            "WebView API 请求结束: method=\(method), path=\(apiPath), status=\(response.statusCode.map(String.init) ?? "nil"), bodyLength=\(response.body.count), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
        )
        // 非 2xx 时把正文前 240 字节落盘：接口报错往往只有一句话，
        // 是判断"缺签名 / 缺参数 / 真限流"的唯一依据，之前只记了长度。
        if let status = response.statusCode, (200..<300).contains(status) == false {
            let snippet = response.body
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            AppLog.warning(
                .webView,
                "WebView API 错误正文 status=\(status) body=\(snippet.prefix(240))"
            )
        }
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
        timeoutInterval: TimeInterval = 20,
        signed: Bool = false,
        requireCleanPage: Bool = true
    ) async throws -> Response {
        let response = try await fetch(
            apiPath: apiPath,
            referer: referer,
            method: method,
            body: body,
            headers: headers,
            timeoutInterval: timeoutInterval,
            requireCleanPage: requireCleanPage,
            signed: signed
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
