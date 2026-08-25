//
//  HTMLClient.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

protocol HTMLClient: Sendable {
    func get(_ url: URL) async throws -> HTMLResponse
    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse
}

/// 详情页在 HTTP 返回了无法解析的页面时，可要求支持方直接使用 WebView 重取一次。
/// 该能力保持可选，避免让测试桩和纯 HTTP 客户端承担 WebKit 生命周期。
protocol WebViewFallbackRetrying: Sendable {
    func getUsingWebViewFallback(_ url: URL) async throws -> HTMLResponse
}
