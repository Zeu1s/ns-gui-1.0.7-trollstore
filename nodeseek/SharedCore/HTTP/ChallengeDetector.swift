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

        // 其余非 2xx 同样不是可用内容。此前 400/404/500 会一路掉到最后的 nil，
        // 于是"站点明确报了错"被当成加载成功、解析出 0 条、界面显示空白——
        // 内版（400 / 44 字节）和站内搜索（500 / 161 字节）都是这么变成
        // 无声"无法加载"的。这里收口，让上层走回退或如实报错。
        if response.statusCode >= 400 {
            return .httpError(status: response.statusCode, url: response.finalURL)
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
        // 用户空间和粉丝列表是另一个单页应用，没有 nsk-body 骨架，
        // 但带服务端渲染标记。不认它，这两类页面会一路掉到挑战判定里。
        let hasStructure = html.contains("data-server-rendered")
            || html.contains("nodeseek")
            || html.contains("nsk-")
        // 挑战标记只用一处定义。此前这里另有一份包含 challenge-platform 的名单，
        // 而那个脚本 NodeSeek 每个正常页面都带，等于自己把自己的页面否决掉。
        return hasContent && hasStructure && !containsCloudflareChallengeHTML(html)
    }
}
