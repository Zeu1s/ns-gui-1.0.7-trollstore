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
        }
    }

    /// 站点应用层限流（429）：重试只会延续限流窗口，必须静默失败。
    var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }
}

nonisolated enum NodeSeekResult<Value: Sendable>: Sendable {
    case value(Value)
    case challenge(ChallengeKind)
}
