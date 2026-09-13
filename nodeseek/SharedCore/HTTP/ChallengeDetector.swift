//
//  ChallengeDetector.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct ChallengeDetector: Sendable {

    func detect(response: HTMLResponse) -> ChallengeKind? {
        if Self.containsLoginRequiredHTML(response.html) {
            return .loginRequired(response.finalURL)
        }

        // 站点应用层限流优先判定：429 的残缺页不含 Cloudflare 标记，
        // 若不提前拦截会被当作可用内容（曾造成"列表加载成功，数量: 0"假成功）。
        if response.statusCode == 429 {
            return .rateLimited(response.finalURL)
        }

        if Self.containsUsableNodeSeekHTML(response.html) {
            return nil
        }

        if isCloudflareChallenge(html: response.html, headers: response.headers) {
            return .cloudflare(response.finalURL)
        }

        if response.statusCode == 403 || response.statusCode == 503 {
            return .blocked(response.finalURL)
        }

        return nil
    }

    private func isCloudflareChallenge(html: String, headers: [String: String]) -> Bool {
        let normalizedHeaders = Dictionary(
            uniqueKeysWithValues: headers.map { key, value in
                (key.lowercased(), value.lowercased())
            }
        )

        // 注意：NodeSeek 正常页面也会带 `Server: cloudflare`，不能仅凭这个头判断 challenge。
        // 仅在 Cloudflare 明确给出 challenge 信号时判定。
        if normalizedHeaders["cf-mitigated"] == "challenge" {
            return true
        }

        return Self.containsCloudflareChallengeHTML(html)
    }

    static func containsCloudflareChallengeHTML(_ html: String) -> Bool {
        HTMLPayloadInspector.containsCloudflareChallenge(html)
    }

    static func containsLoginRequiredHTML(_ html: String) -> Bool {
        html.contains("本帖需要注册用户才能查看")
            || html.contains("需要注册用户才能查看")
    }

    static func containsUsableNodeSeekHTML(_ html: String) -> Bool {
        // 收紧：challenge 页也可能含部分 NodeSeek 标记（如评论容器），
        // 必须同时具备站点骨架与内容特征才认为可用，避免把挑战页当正常页。
        if html.contains("id=\"nsk-body\"") {
            return true
        }
        let hasContent = html.contains("class=\"post-list\"")
            || html.contains("class=\"nsk-post\"")
            || html.contains("class=\"post-content\"")
            || html.contains("class=\"comments\"")
        let hasStructure = html.contains("nodeseek") || html.contains("nsk-")
        return hasContent && hasStructure && !isCloudflareMarked(html)
    }

    private static func isCloudflareMarked(_ html: String) -> Bool {
        html.contains("challenge-platform")
            || html.contains("cf-chl")
            || html.contains("Just a moment")
            || html.contains("cf-please-wait")
    }
}
