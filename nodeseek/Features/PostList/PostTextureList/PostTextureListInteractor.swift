//
//  PostTextureListInteractor.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

@MainActor
final class PostTextureListInteractor: PostTextureListHostInteractorInput {
    
    // MARK: - Properties
    weak var presenter: PostTextureListHostInteractorOutput?
    private let service: NodeSeekService
    private let sessionStore: NodeSeekSessionStore
    private var activeLoadTask: Task<Void, Never>?
    private var loadGeneration = 0
    
    // MARK: - Initialization
    init(
        service: NodeSeekService? = nil,
        sessionStore: NodeSeekSessionStore = .shared
    ) {
        self.service = service ?? NodeSeekService(htmlClient: HTMLLoadingStrategyFactory.makeDefaultClient())
        self.sessionStore = sessionStore
    }
    
    // MARK: - Methods
    func loadPosts(category: PostListCategoryItem, sortMode: PostListSortMode) {
        load(page: 1, category: category, sortMode: sortMode, isLoadMore: false)
    }

    func loadMorePosts(page: Int, category: PostListCategoryItem, sortMode: PostListSortMode) {
        load(page: max(2, page), category: category, sortMode: sortMode, isLoadMore: true)
    }

    private func load(page: Int, category: PostListCategoryItem, sortMode: PostListSortMode, isLoadMore: Bool) {
        loadGeneration &+= 1
        let generation = loadGeneration
        activeLoadTask?.cancel()
        activeLoadTask = Task { [weak self] in
            guard let self else { return }
            AppLog.info(.postList, "开始加载帖子列表，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page), isLoadMore=\(isLoadMore)")
            do {
                let posts = try await self.loadPosts(page: page, category: category, sortMode: sortMode)
                guard Task.isCancelled == false, self.loadGeneration == generation else { return }
                AppLog.info(.postList, "帖子列表加载成功，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page), 数量: \(posts.count)")
                if isLoadMore {
                    self.presenter?.didLoadMorePosts(posts, page: page, category: category, sortMode: sortMode)
                } else {
                    self.presenter?.didLoadPosts(posts, category: category, sortMode: sortMode)
                }
            } catch {
                guard Task.isCancelled == false, self.loadGeneration == generation else { return }
                AppLog.error(.postList, "帖子列表加载失败，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page): \(error.localizedDescription)")
                if isLoadMore {
                    self.presenter?.didFailLoadMorePosts(error: error.localizedDescription, page: page, category: category, sortMode: sortMode)
                } else {
                    self.presenter?.didFailLoadPosts(error: error.localizedDescription, category: category, sortMode: sortMode)
                }
            }
        }
    }
    private func loadPosts(page: Int, category: PostListCategoryItem, sortMode: PostListSortMode) async throws -> [PostSummary] {
        AppLog.info(.postList, "列表请求开始，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page)")
        let result = try await service.loadPostList(page: page, category: category, sortMode: sortMode)
        switch result {
        case .value(let posts):
            await PostSummaryResolver.shared.store(posts)
            await sessionStore.recordSuccess()
            AppLog.info(.postList, "列表请求拿到有效结果，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page)")
            return posts
        case .challenge(let challenge):
            AppLog.warning(.postList, "列表请求命中验证，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page): \(challenge.logDescription)")
            let message = await sessionStore.recordChallenge(challenge)
            throw PostTextureListLoadError.challengeRequired(message)
        }
    }
}

private enum PostTextureListLoadError: LocalizedError {
    case challengeRequired(String)

    var errorDescription: String? {
        switch self {
        case .challengeRequired(let message):
            return message
        }
    }
}
