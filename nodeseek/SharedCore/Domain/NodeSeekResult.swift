//
//  NodeSeekResult.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

nonisolated enum ChallengeKind: Equatable, Sendable {
    case loginRequired(URL)
    case cloudflare(URL)
    case blocked(URL)
    case rateLimited(URL)
    case unsupported(URL)
    /// 站点直接返回 4xx/5xx，且页面里没有可用内容。
    /// 与 `.blocked`（Cloudflare 拦截页）分开建模，是为了把服务端真实状态码
    /// 原样交给用户，而不是把 400/500 一律说成"需要验证"。
    case httpError(status: Int, url: URL)
}

extension ChallengeKind {
    var logDescription: String {
        switch self {
        case .loginRequired(let url):
            return "loginRequired(\(url.absoluteString))"
        case .cloudflare(let url):
            return "cloudflare(\(url.absoluteString))"
        case .blocked(let url):
            return "blocked(\(url.absoluteString))"
        case .rateLimited(let url):
            return "rateLimited(\(url.absoluteString))"
        case .unsupported(let url):
            return "unsupported(\(url.absoluteString))"
        case .httpError(let status, let url):
            return "httpError(\(status), \(url.absoluteString))"
        }
    }

    /// 站点应用层限流（429）：重试只会延续限流窗口，必须静默失败。
    var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    /// 服务端状态码错误。列表和搜索据此直接如实报错；详情页要跳过这个早退，
    /// 好让原有的"解析失败 → WebView 恢复"链路仍然跑一次——那里确实偶有救回。
    var isHTTPError: Bool {
        if case .httpError = self { return true }
        return false
    }
}

nonisolated enum NodeSeekResult<Value: Sendable>: Sendable {
    case value(Value)
    case challenge(ChallengeKind)
}
