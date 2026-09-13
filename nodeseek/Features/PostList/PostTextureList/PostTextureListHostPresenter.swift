//
//  PostTextureListHostPresenter.swift
//  nodeseek
//

import Foundation

final class PostTextureListHostPresenter: PostTextureListHostPresenterProtocol {
    weak var delegate: PostTextureListHostPresenterDelegate?

    private weak var view: PostTextureListHostViewProtocol?
    private let category: PostListCategoryItem
    private let interactor: PostTextureListHostInteractorInput
    private let visitedStore: VisitedPostStoreProtocol
    private var sortMode: PostListSortMode = .replyTime
    private var items: [PostListItem] = []
    private var loadedIDs: Set<String> = []
    private var nextPage: Int = 2
    private var hasMorePages = true
    private var hasLoadedFirstPage = false
    private var isLoadingFirstPage = false
    private var isRefreshing = false
    private var isLoadingMore = false
    private var pendingFirstPageRefresh = false
    private var specialFollowAutoFetchPagesRemaining = 0
    private var temporaryFailureRetryCount = 0
    private var temporaryFailureRetryWorkItem: DispatchWorkItem?

    init(
        category: PostListCategoryItem,
        interactor: PostTextureListHostInteractorInput,
        visitedStore: VisitedPostStoreProtocol
    ) {
        self.category = category
        self.interactor = interactor
        self.visitedStore = visitedStore
        self.interactor.presenter = self
    }

    deinit {
        temporaryFailureRetryWorkItem?.cancel()
    }

    func setView(_ view: PostTextureListHostViewProtocol) {
        self.view = view
    }

    var currentSortMode: PostListSortMode {
        sortMode
    }

    var isReadyForDisplay: Bool {
        hasLoadedFirstPage
    }

    func viewDidLoad() {
        loadFirstPageIfNeeded()
    }

    func toggleSortMode() -> PostListSortMode {
        sortMode = sortMode.toggled
        resetAndLoadFirstPage()
        delegate?.postTextureListHostDidChangeSortMode(sortMode, category: category)
        return sortMode
    }

    func reloadFirstPage() {
        guard hasLoadedFirstPage == false else {
            refreshFirstPageKeepingContent()
            return
        }
        loadFirstPageIfNeeded()
    }

    func ensureFirstPageLoaded() {
        loadFirstPageIfNeeded()
    }
    func refreshFirstPageKeepingContent() {
        guard hasLoadedFirstPage else {
            loadFirstPageIfNeeded()
            return
        }
        guard !isRefreshing, !isLoadingFirstPage else { return }
        guard !isLoadingMore else {
            // 分页请求无法安全取消，完成后补做一次首页刷新，避免双击刷新被静默吞掉。
            pendingFirstPageRefresh = true
            return
        }
        startFirstPageRefresh()
    }

    private func startFirstPageRefresh() {
        isRefreshing = true
        interactor.loadPosts(category: category, sortMode: sortMode)
    }

    /// 板块/tab 重新进入时，若当前没有正在进行的刷新/加载，则重播流式呈现。
    func replayStreamAppearance() {
        guard hasLoadedFirstPage, items.isEmpty == false else { return }
        guard !isRefreshing, !isLoadingFirstPage, !isLoadingMore else { return }
        view?.replayStreamAppearance()
    }

    func didSelectPost(at index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        visitedStore.markVisited(post: item.post, visitedAt: Date())
        if !item.isVisited {
            items[index] = PostListItem(post: item.post, isVisited: true)
            view?.updateVisitedState(at: index, isVisited: true)
        }
        delegate?.postTextureListHostDidSelectPost(item.post, category: category)
    }

    func didRequestRefresh() {
        refreshFirstPage()
    }

    func didRequestFirstPageRetry() {
        reloadFirstPage()
    }
    func didApproachBottom(at index: Int, totalCount: Int) {
        loadMoreIfNeeded(currentIndex: index, totalCount: totalCount)
    }
}

extension PostTextureListHostPresenter: PostTextureListHostInteractorOutput {
    func didLoadPosts(
        _ posts: [PostSummary],
        category: PostListCategoryItem,
        sortMode: PostListSortMode
    ) {
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        items = postItems(for: posts)
        loadedIDs = Set(posts.map(\.id))
        hasMorePages = !posts.isEmpty
        nextPage = 2
        hasLoadedFirstPage = true
        isLoadingFirstPage = false
        isRefreshing = false
        isLoadingMore = false
        pendingFirstPageRefresh = false
        temporaryFailureRetryCount = 0
        temporaryFailureRetryWorkItem?.cancel()
        temporaryFailureRetryWorkItem = nil
        view?.setItems(items)
        view?.hideFirstPageError()
        view?.hideLoadingSkeleton()
        view?.hideRefreshing()
        view?.hideLoadingMore()
        delegate?.postTextureListHostDidLoadFirstPage(category: category)
        if category.isSpecialFollow, items.isEmpty, hasMorePages, specialFollowAutoFetchPagesRemaining == 0 {
            specialFollowAutoFetchPagesRemaining = 6
            fetchNextSpecialFollowPageIfNeeded()
        }
    }

    func didLoadMorePosts(
        _ posts: [PostSummary],
        page: Int,
        category: PostListCategoryItem,
        sortMode: PostListSortMode
    ) {
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        isLoadingMore = false

        guard !posts.isEmpty else {
            hasMorePages = false
            AppLog.info(.postList, "帖子列表加载更多结束: 无更多分页 page=\(page), category=\(category.rawValue)")
            view?.hideLoadingMore()
            runPendingFirstPageRefreshIfNeeded()
            return
        }

        nextPage = page + 1
        var appended = false
        for post in posts where loadedIDs.insert(post.id).inserted {
            items.append(PostListItem(post: post, isVisited: visitedStore.isVisited(postID: post.id)))
            appended = true
        }

        if appended {
            AppLog.info(.postList, "帖子列表加载更多完成: page=\(page), category=\(category.rawValue), received=\(posts.count), total=\(items.count)")
            view?.setItems(items)
        }
        view?.hideLoadingMore()
        runPendingFirstPageRefreshIfNeeded()
        if category.isSpecialFollow, items.isEmpty, specialFollowAutoFetchPagesRemaining > 0 {
            fetchNextSpecialFollowPageIfNeeded()
        }
    }

    func didFailLoadPosts(error: String, category: PostListCategoryItem, sortMode: PostListSortMode) {
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        if scheduleTemporaryFailureRetryIfNeeded(error: error) {
            return
        }
        let failedInitialLoad = hasLoadedFirstPage == false
        isLoadingFirstPage = false
        isRefreshing = false
        isLoadingMore = false
        pendingFirstPageRefresh = false
        view?.hideLoadingSkeleton()
        view?.hideRefreshing()
        view?.hideLoadingMore()
        if items.isEmpty {
            view?.showFirstPageError(message: error)
        }
        if failedInitialLoad {
            delegate?.postTextureListHostDidFailInitialLoad(category: category)
        }
    }

    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategoryItem, sortMode: PostListSortMode) {
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        isLoadingMore = false
        AppLog.warning(.postList, "帖子列表加载更多失败: page=\(page), category=\(category.rawValue), error=\(error)")
        view?.hideLoadingMore()
        runPendingFirstPageRefreshIfNeeded()
    }
}

private extension PostTextureListHostPresenter {
    func resetAndLoadFirstPage() {
        temporaryFailureRetryWorkItem?.cancel()
        temporaryFailureRetryWorkItem = nil
        temporaryFailureRetryCount = 0
        items = []
        loadedIDs = []
        nextPage = 2
        hasMorePages = true
        hasLoadedFirstPage = false
        isRefreshing = false
        isLoadingMore = false
        pendingFirstPageRefresh = false
        view?.setItems([])
        view?.hideFirstPageError()
        loadFirstPageIfNeeded()
    }

    func loadFirstPageIfNeeded() {
        guard !hasLoadedFirstPage else { return }
        guard !isLoadingFirstPage else { return }
        isLoadingFirstPage = true
        isRefreshing = false
        isLoadingMore = false
        view?.showLoadingSkeleton()
        view?.hideFirstPageError()
        view?.hideRefreshing()
        view?.hideLoadingMore()
        interactor.loadPosts(category: category, sortMode: sortMode)
    }

    func refreshFirstPage() {
        refreshFirstPageKeepingContent()
    }

    func runPendingFirstPageRefreshIfNeeded() {
        guard pendingFirstPageRefresh else { return }
        pendingFirstPageRefresh = false
        refreshFirstPageKeepingContent()
    }

    func loadMoreIfNeeded(currentIndex: Int, totalCount: Int) {
        guard totalCount > 0 else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: totalCount=0")
            return
        }
        guard hasMorePages else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: 已无更多分页 category=\(category.rawValue)")
            return
        }
        guard !isLoadingMore else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: 正在加载更多 category=\(category.rawValue)")
            return
        }
        guard !isLoadingFirstPage, !isRefreshing else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: 首屏仍在加载 category=\(category.rawValue)")
            return
        }

        isLoadingMore = true
        AppLog.info(
            .postList,
            "触发帖子列表加载更多: page=\(nextPage), category=\(category.rawValue), sortMode=\(sortMode.rawValue), currentIndex=\(currentIndex), totalCount=\(totalCount)"
        )
        view?.showLoadingMore()
        interactor.loadMorePosts(page: nextPage, category: category, sortMode: sortMode)
    }

    func scheduleTemporaryFailureRetryIfNeeded(error: String) -> Bool {
        guard temporaryFailureRetryCount < 1 else { return false }
        let normalizedError = error.lowercased()
        let isTemporaryFailure = normalizedError.contains("503")
            || normalizedError.contains("429")
            || normalizedError.contains("service unavailable")
            || normalizedError.contains("cloudflare")
            || normalizedError.contains("too many requests")
            || normalizedError.contains("请求过于频繁")
            || normalizedError.contains("network connection was lost")
            || normalizedError.contains("network is offline")
            || normalizedError.contains("timed out")
            || normalizedError.contains("not connected to the internet")
        guard isTemporaryFailure else {
            return false
        }

        // Cloudflare 封禁是 IP 级且持续的：立即自动重试只会加重封禁。
        // 命中 cloudflare / 429 / too many requests 时不自动重试，等用户手动下拉。
        let isRateOrChallenge = normalizedError.contains("cloudflare")
            || normalizedError.contains("429")
            || normalizedError.contains("too many requests")
            || normalizedError.contains("403")
            || normalizedError.contains("blocked")
        if isRateOrChallenge {
            AppLog.warning(.postList, "命中 Cloudflare/限流，暂停自动重试避免加重封禁: category=\(category.rawValue)")
            return true
        }

        temporaryFailureRetryCount += 1
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.temporaryFailureRetryWorkItem = nil
            self.interactor.loadPosts(category: self.category, sortMode: self.sortMode)
        }
        temporaryFailureRetryWorkItem?.cancel()
        temporaryFailureRetryWorkItem = workItem
        let retryDelay: TimeInterval = 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: workItem)
        AppLog.warning(.postList, "帖子列表遇到临时网络错误，保留当前内容并自动重试一次: category=\(category.rawValue)")
        return true
    }

    private func fetchNextSpecialFollowPageIfNeeded() {
        guard category.isSpecialFollow else { return }
        guard specialFollowAutoFetchPagesRemaining > 0 else { return }
        guard !isLoadingMore, !isLoadingFirstPage, !isRefreshing else { return }
        guard hasMorePages else { return }
        specialFollowAutoFetchPagesRemaining -= 1
        isLoadingMore = true
        view?.showLoadingMore()
        interactor.loadMorePosts(page: nextPage, category: category, sortMode: sortMode)
    }
    func postItems(for posts: [PostSummary]) -> [PostListItem] {
        let filteredPosts: [PostSummary]
        if category.isSpecialFollow {
            let rules = SpecialFollowKeywordStore.shared.rules
            filteredPosts = posts.filter { post in
                rules.contains { rule in
                    post.title.localizedCaseInsensitiveContains(rule.keyword)
                }
            }
        } else {
            filteredPosts = posts
        }
        return filteredPosts.map { post in
            PostListItem(post: post, isVisited: visitedStore.isVisited(postID: post.id))
        }
    }
}
