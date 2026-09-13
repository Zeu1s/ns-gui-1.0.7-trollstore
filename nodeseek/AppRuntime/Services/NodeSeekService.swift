//
//  NodeSeekService.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

enum NodeSeekPostDetailLoadingError: LocalizedError, Equatable {
    case notFound(postID: String, page: Int)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "帖子或该评论页不存在，可能已删除或页码无效。"
        }
    }
}

struct NodeSeekService: Sendable {
    let baseURL: URL
    private let htmlClient: any HTMLClient
    private let parser: any NodeSeekParser
    private let challengeDetector: ChallengeDetector
    private let currentAccountStore: CurrentAccountStore?

    init(
        baseURL: URL = NodeSeekSite.baseURL,
        htmlClient: any HTMLClient = HiddenWebViewHTMLClient(),
        parser: (any NodeSeekParser)? = nil,
        challengeDetector: ChallengeDetector = ChallengeDetector(),
        currentAccountStore: CurrentAccountStore? = .shared
    ) {
        self.baseURL = baseURL
        self.htmlClient = htmlClient
        self.parser = parser ?? KannaNodeSeekParser(
            baseURL: baseURL,
            debugLogger: { AppLog.debug(.account, $0) }
        )
        self.challengeDetector = challengeDetector
        self.currentAccountStore = currentAccountStore
    }

    func loadPostList(
        page: Int = 1,
        category: PostListCategoryItem = .all,
        sortMode: PostListSortMode = .replyTime
    ) async throws -> NodeSeekResult<[PostSummary]> {
        let targetURL = postListURL(page: page, category: category, sortMode: sortMode)
        AppLog.info(.service, "开始抓取 NodeSeek 列表，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        AppLog.info(.service, "抓取返回 category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")

        if let challenge = challengeDetector.detect(response: response) {
            AppLog.warning(.service, "检测到 challenge: \(challenge.logDescription)")
            return .challenge(challenge)
        }

        await updateCurrentAccountIfPresent(in: response.html)
        let posts = try parser.parsePostList(html: response.html)
        AppLog.info(.service, "列表解析完成，帖子数量: \(posts.count)")
        return .value(posts)
    }

    func loadSearchResults(
        query: String,
        page: Int = 1,
        category: PostListCategory = .all
    ) async throws -> NodeSeekResult<[PostSummary]> {
        let targetURL = searchURL(query: query, page: page, category: category)
        AppLog.info(.service, "开始抓取 NodeSeek 搜索，category=\(category.rawValue), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        AppLog.info(.service, "搜索抓取返回 category=\(category.rawValue), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")

        if let challenge = challengeDetector.detect(response: response) {
            AppLog.warning(.service, "检测到搜索 challenge: \(challenge.logDescription)")
            return .challenge(challenge)
        }

        await updateCurrentAccountIfPresent(in: response.html)
        let posts = try parser.parsePostList(html: response.html)
        AppLog.info(.service, "搜索解析完成，帖子数量: \(posts.count)")
        return .value(posts)
    }

    func loadAccount() async throws -> NodeSeekResult<AccountResponse> {
        let targetURL = baseURL
        AppLog.info(.service, "开始抓取 NodeSeek 账号信息: \(targetURL.absoluteString)")
        AppLog.debug(.account, "service: request \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        AppLog.info(.service, "账号信息抓取返回 status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")
        AppLog.debug(
            .account,
            "service: response status=\(response.statusCode) len=\(response.html.count) final=\(response.finalURL.path) userCard=\(response.html.contains("user-card")) usercardMe=\(response.html.contains("usercard-me")) tempScript=\(response.html.contains("temp-script")) capturedConfig=\(response.html.contains("nodeseek-captured-config")) memberID=\(response.html.contains("member_id"))"
        )

        if let challenge = challengeDetector.detect(response: response) {
            AppLog.warning(.service, "检测到账号信息 challenge: \(challenge.logDescription)")
            AppLog.debug(.account, "service: challenge \(challenge.logDescription)")
            return .challenge(challenge)
        }

        let account = try parser.parseAccount(html: response.html)
        await currentAccountStore?.save(account)
        AppLog.info(.service, "账号信息解析完成，loggedIn=\(account.isLoggedIn), displayName=\(account.displayName)")
        AppLog.debug(.account, "service: parsed loggedIn=\(account.isLoggedIn) name=\(account.displayName) avatar=\(account.avatarURL?.path ?? "nil") profile=\(account.profileURL?.path ?? "nil") stats=\(account.stats.joined(separator: "|"))")
        return .value(account)
    }

    func loadPostDetail(postID: String, page: Int = 1) async throws -> NodeSeekResult<PostDetail> {
        let targetURL = postDetailURL(postID: postID, page: page)
        AppLog.info(.service, "开始抓取 NodeSeek 详情，postID=\(postID), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        AppLog.info(.service, "详情抓取返回 postID=\(postID), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")

        guard response.statusCode != 404 else {
            AppLog.warning(.service, "详情页不存在，跳过 WebView 回退与解析: postID=\(postID), page=\(page)")
            throw NodeSeekPostDetailLoadingError.notFound(postID: postID, page: page)
        }

        if let challenge = challengeDetector.detect(response: response) {
            AppLog.warning(.service, "检测到详情 challenge: \(challenge.logDescription)")
            return .challenge(challenge)
        }

        await updateCurrentAccountIfPresent(in: response.html)
        let detail: PostDetail
        do {
            detail = try parser.parsePostDetail(html: response.html, url: targetURL)
        } catch NodeSeekParserError.postDetailNotFound {
            // 限流残缺页重打只会延续限流窗口，直接按限流上抛。
            if challengeDetector.detect(response: response)?.isRateLimited == true {
                AppLog.warning(.service, "详情命中站点限流(429)，停止 WebView 恢复: postID=\(postID), page=\(page)")
                return .challenge(.rateLimited(targetURL))
            }
            guard let fallbackClient = htmlClient as? any WebViewFallbackRetrying else {
                throw NodeSeekParserError.postDetailNotFound
            }

            AppLog.warning(.service, "详情 HTTP 页面无法解析，尝试 WebView 页面恢复，postID=\(postID), page=\(page)")
            let fallbackResponse = try await fallbackClient.getUsingWebViewFallback(targetURL)
            if let challenge = challengeDetector.detect(response: fallbackResponse) {
                AppLog.warning(.service, "WebView 恢复仍命中 challenge: \(challenge.logDescription)")
                return .challenge(challenge)
            }
            await updateCurrentAccountIfPresent(in: fallbackResponse.html)
            detail = try parser.parsePostDetail(html: fallbackResponse.html, url: targetURL)
        }
        AppLog.info(.service, "详情解析完成，postID=\(detail.id), 评论数量: \(detail.comments.count)")
        return .value(detail)
    }

    private func postListURL(page: Int, category: PostListCategoryItem, sortMode: PostListSortMode) -> URL {
        let url = category.pathComponents(page: page).reduce(baseURL) { partialURL, pathComponent in
            partialURL.appendingPathComponent(pathComponent)
        }
        return url.appendingSortQuery(sortMode)
    }

    private func postDetailURL(postID: String, page: Int) -> URL {
        if baseURL == NodeSeekSite.baseURL {
            return NodeSeekSite.postURL(id: postID, page: page)
        }
        return baseURL.appendingPathComponent("post-\(postID)-\(max(1, page))")
    }

    private func searchURL(query: String, page: Int, category: PostListCategory) -> URL {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: true
        ) else {
            return baseURL.appendingPathComponent("search")
        }

        var queryItems = [URLQueryItem(name: "q", value: query)]
        let normalizedPage = max(1, page)
        if normalizedPage > 1 {
            queryItems.append(URLQueryItem(name: "page", value: "\(normalizedPage)"))
        }
        if let categoryValue = category.searchQueryValue {
            queryItems.append(URLQueryItem(name: "category", value: categoryValue))
        }
        components.queryItems = queryItems
        return components.url ?? baseURL.appendingPathComponent("search")
    }

    private func updateCurrentAccountIfPresent(in html: String) async {
        guard let currentAccountStore else { return }
        guard htmlContainsCurrentAccountSignal(html) else { return }

        do {
            let account = try parser.parseAccount(html: html)
            guard account.isLoggedIn else { return }
            await currentAccountStore.save(account)
            AppLog.debug(.account, "service: opportunistic account save -> loggedIn=\(account.isLoggedIn) name=\(account.displayName)")
        } catch {
            AppLog.debug(.account, "service: opportunistic account parse failed \(error.localizedDescription)")
        }
    }

    private func htmlContainsCurrentAccountSignal(_ html: String) -> Bool {
        html.contains("user-card")
            || html.contains(#"id="temp-script""#)
            || html.contains(#"id='temp-script'"#)
            || html.contains("nodeseek-captured-config")
    }
}

private extension URL {
    func appendingSortQuery(_ sortMode: PostListSortMode) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return self
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "sortBy" }
        queryItems.append(URLQueryItem(name: "sortBy", value: sortMode.rawValue))
        components.queryItems = queryItems
        return components.url ?? self
    }
}

/// 将首页已解析的帖子摘要复用于历史、主题帖和收藏页。
/// 用户内容接口本身是统计的主来源；这里仅用于补充已加载过首页帖子的
/// 头像、作者和缺失统计，绝不把帖子标题提交给搜索服务。
actor PostSummaryResolver {
    static let shared = PostSummaryResolver()

    private var cachedSummaries: [String: PostSummary] = [:]
    private var inFlightRequests: [String: Task<PostSummary?, Never>] = [:]

    func store(_ summaries: [PostSummary]) {
        for summary in summaries where summary.id.isEmpty == false {
            cachedSummaries[summary.id] = summary
        }
    }

    func summary(for postID: String) -> PostSummary? {
        cachedSummaries[postID]
    }

    func resolve(postID: String) -> PostSummary? {
        cachedSummaries[postID]
    }

    /// 历史记录没有作者头像时，直接读取该帖的站内详情补齐元数据。
    /// 帖子详情并不提供可靠的总浏览/回复数，因此这些统计始终沿用调用方
    /// 已经取得的数值，避免以 0 覆盖真实数据。
    func resolveHistoryMetadata(
        postID: String,
        title: String,
        fallbackViewCount: Int,
        fallbackReplyCount: Int
    ) async -> PostSummary? {
        guard postID.isEmpty == false else { return nil }

        if let cached = cachedSummaries[postID],
           cached.avatarURL != nil,
           cached.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           cached.nodeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return merged(
                cached,
                fallbackViewCount: fallbackViewCount,
                fallbackReplyCount: fallbackReplyCount
            )
        }
        if let request = inFlightRequests[postID] {
            guard let loaded = await request.value else { return cachedSummaries[postID] }
            return merged(
                loaded,
                fallbackViewCount: fallbackViewCount,
                fallbackReplyCount: fallbackReplyCount
            )
        }

        let request = Task { () -> PostSummary? in
            do {
                let result = try await NodeSeekService().loadPostDetail(postID: postID)
                guard case let .value(detail) = result else { return nil }
                return PostSummary(
                    id: detail.id,
                    title: detail.title.isEmpty ? title : detail.title,
                    url: NodeSeekSite.postURL(id: detail.id, page: max(1, detail.page)),
                    authorName: detail.authorName,
                    nodeName: detail.categoryWord ?? Self.nodeName(from: detail.metadataText),
                    replyCount: max(fallbackReplyCount, detail.comments.count),
                    viewCount: max(fallbackViewCount, detail.viewCountFromDetail ?? 0),
                    lastActivityText: Self.lastActivityText(from: detail),
                    avatarURL: detail.avatarURL,
                    authorProfileURL: detail.authorProfileURL,
                    authorBadgeTexts: detail.authorBadgeTexts
                )
            } catch {
                return nil
            }
        }
        inFlightRequests[postID] = request
        let resolved = await request.value
        inFlightRequests[postID] = nil
        if let resolved {
            cachedSummaries[postID] = resolved
        }
        return resolved
    }

    private static func lastActivityText(from detail: PostDetail) -> String? {
        if let last = detail.comments.last {
            let author = AuthorDisplayPolicy.displayName(from: last.authorName) ?? last.authorName
            let time = last.createdAtText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = [author, time].compactMap { value in
                value?.isEmpty == false ? value : nil
            }
            if parts.isEmpty == false {
                return parts.joined(separator: " · ")
            }
        }
        return detail.metadataText
    }

    private static func nodeName(from metadataText: String?) -> String? {
        let segments = (metadataText ?? "")
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard segments.count > 1,
              let name = segments.last,
              name.isEmpty == false else {
            return nil
        }
        return name
    }

    private func merged(
        _ summary: PostSummary,
        fallbackViewCount: Int,
        fallbackReplyCount: Int
    ) -> PostSummary {
        PostSummary(
            id: summary.id,
            title: summary.title,
            url: summary.url,
            authorName: summary.authorName,
            nodeName: summary.nodeName,
            replyCount: max(summary.replyCount, fallbackReplyCount),
            viewCount: max(summary.viewCount, fallbackViewCount),
            createdAtText: summary.createdAtText,
            lastActivityText: summary.lastActivityText,
            isPinned: summary.isPinned,
            isLocked: summary.isLocked,
            requiredReadingLevel: summary.requiredReadingLevel,
            avatarURL: summary.avatarURL,
            authorProfileURL: summary.authorProfileURL,
            authorBadgeTexts: summary.authorBadgeTexts
        )
    }
}
