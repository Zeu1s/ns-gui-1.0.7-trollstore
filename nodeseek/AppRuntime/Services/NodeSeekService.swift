//
//  NodeSeekService.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

enum NodeSeekPostDetailLoadingError: LocalizedError, Equatable {
    case notFound(postID: String, page: Int)
    /// 站点没有"删除帖子"这个操作，作者能做的只有把帖子设为私有，
    /// 于是没权限的访客拿到的就是 404。实测来源：游客请求 post-938518-1
    /// 返回 404，正文 `#nsk-body-left` 里是「本帖需要注册用户才能查看😭」。
    /// 所以 404 不等于"已删除"，必须按正文分开判。
    case restricted(postID: String, page: Int)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "帖子或该评论页不存在，可能已删除或页码无效。"
        case .restricted:
            return "该帖子已私有化或需要权限，当前账号看不到内容。"
        }
    }
}

struct NodeSeekService: Sendable {
    let baseURL: URL
    private let htmlClient: any HTMLClient
    private let parser: any NodeSeekParser
    private let challengeDetector: ChallengeDetector
    private let currentAccountStore: CurrentAccountStore?

    /// 与 `XPathRules.postDetailRestrictedNotice` 同一批标记：这条规则早就用在
    /// HTTP 200 的受限页面上，404 页面复用它不是新猜的说法。
    private static let restrictedPostMarkers = [
        "需要注册用户才能查看",
        "权限不足",
        "restricted-post"
    ]

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
            logErrorBodyIfNeeded(response, phase: "列表")
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
            logErrorBodyIfNeeded(response, phase: "搜索")
            return .challenge(challenge)
        }

        await updateCurrentAccountIfPresent(in: response.html)
        let posts = try parser.parsePostList(html: response.html)
        AppLog.info(.service, "搜索解析完成，帖子数量: \(posts.count)")
        return .value(posts)
    }

    /// 失败响应的正文常常只有几十到几百字节，却是定位服务端真实原因的唯一线索。
    /// 内版 400 的 44 字节、搜索 500 的 161 字节此前都没有落进日志。
    private func logErrorBodyIfNeeded(_ response: HTMLResponse, phase: String) {
        guard response.statusCode >= 400 else { return }
        let flattened = response.html
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let limit = 240
        let body = flattened.count > limit
            ? String(flattened.prefix(limit)) + "…"
            : flattened
        AppLog.warning(.service, "\(phase)错误响应正文 status=\(response.statusCode) body=\(body)")
    }

    /// 404 页面的前 240 个字符全是 `<head>` 骨架，站点说明"为什么打不开"的那句话
    /// 在 `#nsk-body-left` 里，正好被截掉。上一份日志 6 个 404 因此一个都没分类出来
    /// （全落到"正文无权限提示"），所以单独把这块正文的可见文字取出来。
    private func log404BodyText(_ html: String, postID: String) {
        guard let start = html.range(of: "id=\"nsk-body-left\"") else {
            AppLog.warning(.service, "详情 404 无正文容器: postID=\(postID)")
            return
        }
        let chunk = String(html[start.upperBound...].prefix(4000))
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ")
        let text = chunk.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        AppLog.warning(.service, "详情 404 正文文字 postID=\(postID): \(String(text.prefix(180)))")
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
        AppLogMetrics.shared.record(.detailRequests)
        AppLog.info(.service, "开始抓取 NodeSeek 详情，postID=\(postID), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        // 投票挂载点在服务端 HTML 里到底存不存在，决定了"没有投票就不开 WebView"
        // 这条优化能不能做。真机才能拿到这份 HTML，所以先把答案打在既有那行上。
        AppLog.info(.service, "详情抓取返回 postID=\(postID), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.count), 投票挂载点=\(response.html.contains("vote-editor-mount")), finalURL=\(response.finalURL.absoluteString)")

        guard response.statusCode != 404 else {
            // 原来这里只看状态码就断言"不存在"，正文一眼都没看过。站点没有删除功能，
            // 私有化后的帖子同样返回 404，两者对用户的说法完全不同。
            logErrorBodyIfNeeded(response, phase: "详情")
            let isRestricted = Self.restrictedPostMarkers.contains { response.html.contains($0) }
            AppLog.warning(
                .service,
                "详情 404 分类: postID=\(postID), page=\(page), 判定=\(isRestricted ? "私有化或需要权限" : "正文无权限提示"), htmlLength=\(response.html.count)"
            )
            log404BodyText(response.html, postID: postID)
            throw isRestricted
                ? NodeSeekPostDetailLoadingError.restricted(postID: postID, page: page)
                : NodeSeekPostDetailLoadingError.notFound(postID: postID, page: page)
        }

        // 服务端状态码错误不在这里早退：详情页下面那条"解析失败 → WebView 恢复"
        // 链路对这类页面仍有可能救回来，早退会把它一起跳过。
        if let challenge = challengeDetector.detect(response: response),
           challenge.isHTTPError == false {
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
    /// 失败冷却截止时间。缺了它，每次进历史页都会把同一批帖子原封不动重打，
    /// 是站点 429 的主要来源。
    private var failedRequests: [String: Date] = [:]
    private static let failedSummaryRetryInterval: TimeInterval = 600

    /// 摘要缓存上限：每次翻页都会把整页摘要塞进来，只增不减会随浏览时长一直涨。
    /// 超限时按写入顺序淘汰最早的（首页/历史页靠前的帖子被复用概率最高，
    /// 被淘汰的重新解析即可）。
    private static let maximumCachedSummaryCount = 2_000
    private var cachedSummaryInsertionOrder: [String] = []

    private func evictCachedSummariesIfNeeded() {
        while cachedSummaryInsertionOrder.count > Self.maximumCachedSummaryCount {
            let oldest = cachedSummaryInsertionOrder.removeFirst()
            cachedSummaries.removeValue(forKey: oldest)
        }
    }

    func store(_ summaries: [PostSummary]) {
        for summary in summaries where summary.id.isEmpty == false {
            if cachedSummaries[summary.id] == nil {
                cachedSummaryInsertionOrder.append(summary.id)
            }
            cachedSummaries[summary.id] = summary
        }
        evictCachedSummariesIfNeeded()
    }

    func summary(for postID: String) -> PostSummary? {
        cachedSummaries[postID]
    }

    /// 用户刚在这个帖子上做过事（发回复、编辑），缓存里的回复数就可能旧了。
    /// "抓成功过就算命中"这条优化会让这种帖子一直显示旧值，所以要留一个失效入口。
    func invalidate(postID: String) {
        cachedSummaries[postID] = nil
        failedRequests[postID] = nil
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

        // 抓成功过就算命中，不再要求头像/作者/板块名三项都齐。
        // 收藏接口本身不带板块名，抓回来的详情也可能确实没有板块，
        // 用字段齐不齐当命中条件等于让这批帖子永远未命中、
        // 每次进收藏页原封不动重打一遍。
        if let cached = cachedSummaries[postID] {
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

        // 冷却期内不再为同一条重打详情，直接回落到已有的部分缓存（可能为 nil，
        // 历史页本来就带标题和统计，缺的只是头像和板块名）。
        if let retryDate = failedRequests[postID] {
            if retryDate > Date() {
                return cachedSummaries[postID]
            }
            failedRequests[postID] = nil
        }

        // 熔断窗口内直接放弃这次补全，也不排队等下去：板块名和头像只是装饰，
        // 限流期间继续试只会把窗口拖得更长。
        let pacer = NodeSeekDetailRequestPacer.shared
        if await pacer.isCoolingDown() {
            await pacer.noteCooldownSkip()
            return cachedSummaries[postID]
        }

        let request = Task { () -> PostSummary? in
            await pacer.acquire()
            let resolved: PostSummary?
            do {
                // 历史页会一次刷新几十条；默认构造的 NodeSeekService 直连隐藏
                // WebView，会串行占锁几十秒拖死其它 WebView 动作（表现为卡死）。
                // 这里必须走 HTTP 优先的标准客户端。
                let result = try await NodeSeekService(
                    htmlClient: HTMLLoadingStrategyFactory.makeDefaultClient()
                ).loadPostDetail(postID: postID)
                switch result {
                case .value(let detail):
                    resolved = PostSummary(
                        id: detail.id,
                        title: detail.title.isEmpty ? title : detail.title,
                        url: NodeSeekSite.postURL(id: detail.id, page: max(1, detail.page)),
                        authorName: detail.authorName,
                        nodeName: detail.categoryWord ?? Self.nodeName(from: detail.metadataText),
                        // 只有详情页确实只有一页时，comments.count 才是回复总数。
                        // 否则它是"第一页的条数"（站点默认约 10），拿它当总数
                        // 会把长帖压成 10 —— 收藏页数字不准的第二个成因。
                        replyCount: detail.isLastPage
                            ? max(fallbackReplyCount, detail.comments.count)
                            : fallbackReplyCount,
                        viewCount: max(fallbackViewCount, detail.viewCountFromDetail ?? 0),
                        lastActivityText: Self.lastActivityText(from: detail),
                        avatarURL: detail.avatarURL,
                        authorProfileURL: detail.authorProfileURL,
                        authorBadgeTexts: detail.authorBadgeTexts
                    )
                case .challenge(let challenge):
                    if case .rateLimited = challenge {
                        await pacer.noteRateLimited()
                    }
                    resolved = nil
                }
            } catch {
                resolved = nil
            }
            await pacer.release()
            return resolved
        }
        inFlightRequests[postID] = request
        let resolved = await request.value
        inFlightRequests[postID] = nil
        if let resolved {
            cachedSummaries[postID] = resolved
        } else {
            // 失败也要记一笔。此前失败不留任何痕迹，于是每次进历史页都会把
            // 那几十条原封不动重打一遍 —— 这是站点 429 的主要来源。
            // 元数据只是头像和板块名，缺 10 分钟远比把站点打到限流好。
            failedRequests[postID] = Date().addingTimeInterval(Self.failedSummaryRetryInterval)
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
