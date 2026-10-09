//
//  PostDetailInteractor.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

@MainActor
class PostDetailInteractor: PostDetailInteractorInput {
    private enum FavoriteAction {
        case add
        case remove
    }

    private enum DetailLoadOutcome {
        case detail(PostDetail)
        case loginRequired(String)
    }
    
    // MARK: - Properties
    weak var presenter: PostDetailInteractorOutput?
    private let post: PostSummary?
    private let service: NodeSeekService
    private let initialPage: Int
    private let commentSubmitter: NodeSeekCommentSubmitter
    private let collectionSubmitter: PostCollectionSubmitting
    private let postUpvoteSubmitter: PostUpvoteSubmitting
    private let commentUpvoteSubmitter: CommentUpvoteSubmitting
    private let postChickenLegSubmitter: PostChickenLegSubmitting
    private let commentChickenLegSubmitter: CommentChickenLegSubmitting
    private let postDislikeSubmitter: PostDislikeSubmitting
    private let commentDislikeSubmitter: CommentDislikeSubmitting
    private let postVoteSubmitter: PostVoteSubmitting
    private let sessionStore: NodeSeekSessionStore
    private var currentActionPageURL: URL?
    private var detailLoadTask: Task<Void, Never>?
    private var voteLoadTask: Task<Void, Never>?
    private var requestedVotePostID: String?
    private var detailLoadGeneration = 0
    
    // MARK: - Initialization
    init(
        post: PostSummary? = nil,
        service: NodeSeekService? = nil,
        commentSubmitter: NodeSeekCommentSubmitter? = nil,
        collectionSubmitter: PostCollectionSubmitting? = nil,
        postUpvoteSubmitter: PostUpvoteSubmitting? = nil,
        commentUpvoteSubmitter: CommentUpvoteSubmitting? = nil,
        postChickenLegSubmitter: PostChickenLegSubmitting? = nil,
        commentChickenLegSubmitter: CommentChickenLegSubmitting? = nil,
        postDislikeSubmitter: PostDislikeSubmitting? = nil,
        commentDislikeSubmitter: CommentDislikeSubmitting? = nil,
        postVoteSubmitter: PostVoteSubmitting? = nil,
        page: Int = 1,
        sessionStore: NodeSeekSessionStore = .shared
    ) {
        self.post = post
        self.service = service ?? NodeSeekService(htmlClient: HTMLLoadingStrategyFactory.makeDefaultClient())
        self.initialPage = max(1, page)
        self.commentSubmitter = commentSubmitter ?? NodeSeekCommentSubmitter()
        self.collectionSubmitter = collectionSubmitter ?? NodeSeekPostCollectionSubmitter()
        self.postUpvoteSubmitter = postUpvoteSubmitter ?? NodeSeekPostUpvoteSubmitter()
        self.commentUpvoteSubmitter = commentUpvoteSubmitter ?? NodeSeekCommentUpvoteSubmitter()
        self.postChickenLegSubmitter = postChickenLegSubmitter ?? NodeSeekPostChickenLegSubmitter()
        self.commentChickenLegSubmitter = commentChickenLegSubmitter ?? NodeSeekCommentChickenLegSubmitter()
        self.postDislikeSubmitter = postDislikeSubmitter ?? NodeSeekPostDislikeSubmitter()
        self.commentDislikeSubmitter = commentDislikeSubmitter ?? NodeSeekCommentDislikeSubmitter()
        self.postVoteSubmitter = postVoteSubmitter ?? NodeSeekPostVoteSubmitter()
        self.sessionStore = sessionStore
    }
    
    deinit {
        detailLoadTask?.cancel()
        voteLoadTask?.cancel()
    }

    // MARK: - Methods
    func loadPostDetail() {
        loadPostDetail(page: initialPage)
    }

    func cancelPendingLoad() {
        guard detailLoadTask != nil || voteLoadTask != nil else { return }
        detailLoadGeneration &+= 1
        detailLoadTask?.cancel()
        voteLoadTask?.cancel()
        detailLoadTask = nil
        AppLog.info(.postDetail, "详情页离开，已取消在途详情请求")
    }

    func loadPostDetail(page: Int) {
        guard let post else {
            presenter?.didFailLoadPostDetail(error: "缺少帖子信息，无法加载详情。")
            return
        }

        let normalizedPage = max(1, page)
        detailLoadGeneration &+= 1
        let requestID = detailLoadGeneration
        detailLoadTask?.cancel()
        voteLoadTask?.cancel()
        let service = service
        let sessionStore = sessionStore
        let postID = post.id

        detailLoadTask = Task { [weak self] in
            AppLog.info(.postDetail, "开始加载帖子详情，postID=\(postID), page=\(normalizedPage), request=\(requestID)")
            for attempt in 0...1 {
                do {
                    let outcome = try await Self.loadDetail(
                        service: service,
                        sessionStore: sessionStore,
                        postID: postID,
                        page: normalizedPage
                    )
                    guard Task.isCancelled == false,
                          let self,
                          self.detailLoadGeneration == requestID else {
                        return
                    }

                    self.detailLoadTask = nil
                    switch outcome {
                    case .detail(let detail):
                        AppLog.info(.postDetail, "帖子详情加载成功，postID=\(detail.id), 评论数量: \(detail.comments.count)")
                        let actionPageURL = NodeSeekSite.postURL(id: detail.id, page: normalizedPage)
                        self.currentActionPageURL = actionPageURL
                        self.presenter?.didLoadPostDetail(PostDetailResponse(detail: detail))
                        if self.requestedVotePostID != detail.id {
                            self.requestedVotePostID = detail.id
                            self.loadPostVote(postID: detail.id, pageURL: actionPageURL)
                        }
                    case .loginRequired(let message):
                        self.presenter?.didRequireLogin(message: message)
                    }
                    return
                } catch {
                    guard Task.isCancelled == false,
                          Self.isCancelledLoad(error) == false else {
                        return
                    }
                    if attempt == 0, Self.isTemporaryServerError(error) {
                        AppLog.warning(.postDetail, "帖子详情加载遇到临时错误，自动后台重试，postID=\(postID)")
                        do {
                            try await Task.sleep(nanoseconds: 700_000_000)
                        } catch {
                            return
                        }
                        continue
                    }
                    guard let self, self.detailLoadGeneration == requestID else {
                        return
                    }
                    self.detailLoadTask = nil
                    AppLog.error(.postDetail, "帖子详情加载失败，postID=\(postID): \(error.localizedDescription)")
                    self.presenter?.didFailLoadPostDetail(error: error.localizedDescription)
                    return
                }
            }
        }
    }

    private static func isTemporaryServerError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code != NSURLErrorCancelled
        }

        let message = error.localizedDescription.lowercased()
        // 429 不在名单里：它不是"再试一次就好"，而是"你已经超线了"。
        // 站点限制实测为每 2 秒一次，而这里的自动重试只隔 700 毫秒，
        // 等于自己给限流窗口续命（一次会话 130 次 429 有相当部分来自这里）。
        // 用户手动下拉刷新仍然会重新请求。
        return ["500", "502", "503", "504", "timed out", "timeout", "service unavailable", "process terminated"]
            .contains { message.contains($0) }
    }

    func submitReply(content: String) {
        let startedAt = Date()
        AppLog.info(.postDetail, "Interactor 收到提交回复请求: contentLength=\(content.count), hasPost=\(post != nil)")
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else {
            AppLog.warning(.postDetail, "Interactor 中止提交回复: 内容为空, elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
            presenter?.didFailSubmitReply(error: "回复内容不能为空。")
            return
        }

        guard let post else {
            AppLog.error(.postDetail, "Interactor 中止提交回复: 缺少帖子信息, elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
            presenter?.didFailSubmitReply(error: "缺少帖子信息，无法发表评论。")
            return
        }

        let referer = actionReferer(for: post)
        AppLog.info(.postDetail, "Interactor 创建提交回复 Task: postID=\(post.id), referer=\(referer.absoluteString), trimmedLength=\(trimmedContent.count), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        Task {
            let taskStartedAt = Date()
            AppLog.info(.postDetail, "Interactor 提交回复 Task 开始: postID=\(post.id), elapsedFromTapMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
            do {
                AppLog.info(.postDetail, "Interactor 即将调用 commentSubmitter: postID=\(post.id), elapsedMs=\(AppLog.elapsedMilliseconds(since: taskStartedAt))")
                let response = try await commentSubmitter.submitComment(
                    postID: post.id,
                    content: trimmedContent,
                    referer: referer
                )
                AppLog.info(.postDetail, "Interactor commentSubmitter 成功返回: postID=\(post.id), message=\(response.message ?? "nil"), elapsedMs=\(AppLog.elapsedMilliseconds(since: taskStartedAt))")
                await sessionStore.recordSuccess()
                // 刚回过的帖子，缓存里的回复数已经是旧的了 —— 元数据缓存是
                // "抓过就算命中"，不主动失效会一直显示回帖前的数字。
                await PostSummaryResolver.shared.invalidate(postID: post.id)
                AppLog.info(.postDetail, "Interactor 已记录会话成功，准备回调 Presenter: postID=\(post.id), elapsedMs=\(AppLog.elapsedMilliseconds(since: taskStartedAt))")
                await MainActor.run {
                    presenter?.didSubmitReply(PostDetailSubmitReplyResponse(message: response.message))
                }
            } catch {
                AppLog.error(.postDetail, "Interactor 回复提交失败: postID=\(post.id), error=\(error.localizedDescription), elapsedMs=\(AppLog.elapsedMilliseconds(since: taskStartedAt))")
                await MainActor.run {
                    presenter?.didFailSubmitReply(error: error.localizedDescription)
                }
            }
        }
    }

    func submitVote(optionIDs: [String]) {
        let values = Array(Set(optionIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { $0.isEmpty == false }
        guard values.isEmpty == false else {
            presenter?.didFailSubmitPostVote(error: "请先选择投票选项。")
            return
        }
        guard let pageURL = currentActionPageURL else {
            presenter?.didFailSubmitPostVote(error: "帖子页面尚未准备完成，请稍后重试。")
            return
        }
        let submitter = postVoteSubmitter
        Task { [weak self] in
            do {
                let response = try await submitter.submitVote(optionIDs: values, referer: pageURL)
                guard let self else { return }
                self.presenter?.didSubmitPostVote(response)
            } catch {
                guard let self else { return }
                self.presenter?.didFailSubmitPostVote(error: error.localizedDescription)
            }
        }
    }
    func addFavorite() {
        submitFavorite(action: .add)
    }

    func removeFavorite() {
        submitFavorite(action: .remove)
    }

    func addPostLike() {
        guard let post else {
            presenter?.didFailAddPostLike(error: "缺少帖子信息，无法点赞。")
            return
        }

        let referer = actionReferer(for: post)
        Task {
            AppLog.info(.postDetail, "开始点赞帖子，postID=\(post.id)")
            do {
                let response = try await postUpvoteSubmitter.addUpvote(postID: post.id, referer: referer)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddPostLike(response)
                }
            } catch {
                AppLog.error(.postDetail, "点赞帖子失败，postID=\(post.id): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddPostLike(error: error.localizedDescription)
                }
            }
        }
    }

    func addCommentLike(commentID: String) {
        guard let post else {
            presenter?.didFailAddCommentLike(commentID: commentID, error: "缺少帖子信息，无法点赞。")
            return
        }

        let referer = commentReactionReferer(for: post)
        Task {
            AppLog.info(.postDetail, "开始点赞评论，postID=\(post.id), commentID=\(commentID)")
            do {
                let response = try await commentUpvoteSubmitter.addUpvote(commentID: commentID, referer: referer)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddCommentLike(commentID: commentID, response: response)
                }
            } catch {
                AppLog.error(.postDetail, "点赞评论失败，commentID=\(commentID): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddCommentLike(commentID: commentID, error: error.localizedDescription)
                }
            }
        }
    }

    func addPostChickenLeg() {
        guard let post else {
            presenter?.didFailAddPostChickenLeg(error: "缺少帖子信息，无法投放鸡腿。")
            return
        }

        let referer = actionReferer(for: post)
        Task {
            AppLog.info(.postDetail, "开始给帖子投放鸡腿，postID=\(post.id)")
            do {
                let response = try await postChickenLegSubmitter.addChickenLeg(postID: post.id, referer: referer)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddPostChickenLeg(response)
                }
            } catch {
                AppLog.error(.postDetail, "给帖子投放鸡腿失败，postID=\(post.id): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddPostChickenLeg(error: error.localizedDescription)
                }
            }
        }
    }

    func addCommentChickenLeg(commentID: String) {
        guard let post else {
            presenter?.didFailAddCommentChickenLeg(commentID: commentID, error: "缺少帖子信息，无法投放鸡腿。")
            return
        }

        let referer = commentReactionReferer(for: post)
        Task {
            AppLog.info(.postDetail, "开始给评论投放鸡腿，postID=\(post.id), commentID=\(commentID)")
            do {
                let response = try await commentChickenLegSubmitter.addChickenLeg(commentID: commentID, referer: referer)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddCommentChickenLeg(commentID: commentID, response: response)
                }
            } catch {
                AppLog.error(.postDetail, "给评论投放鸡腿失败，commentID=\(commentID): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddCommentChickenLeg(commentID: commentID, error: error.localizedDescription)
                }
            }
        }
    }

    func addPostOppose() {
        guard let post else {
            presenter?.didFailAddPostOppose(error: "缺少帖子信息，无法反对。")
            return
        }

        let referer = actionReferer(for: post)
        Task {
            AppLog.info(.postDetail, "开始反对帖子，postID=\(post.id)")
            do {
                let response = try await postDislikeSubmitter.addDislike(postID: post.id, referer: referer)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddPostOppose(response)
                }
            } catch {
                AppLog.error(.postDetail, "反对帖子失败，postID=\(post.id): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddPostOppose(error: error.localizedDescription)
                }
            }
        }
    }

    func addCommentOppose(commentID: String) {
        guard let post else {
            presenter?.didFailAddCommentOppose(commentID: commentID, error: "缺少帖子信息，无法反对。")
            return
        }

        let referer = commentReactionReferer(for: post)
        Task {
            AppLog.info(.postDetail, "开始反对评论，postID=\(post.id), commentID=\(commentID)")
            do {
                let response = try await commentDislikeSubmitter.addDislike(commentID: commentID, referer: referer)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddCommentOppose(commentID: commentID, response: response)
                }
            } catch {
                AppLog.error(.postDetail, "反对评论失败，commentID=\(commentID): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddCommentOppose(commentID: commentID, error: error.localizedDescription)
                }
            }
        }
    }

    private func submitFavorite(action: FavoriteAction) {
        guard let post else {
            let message = "缺少帖子信息，无法收藏。"
            switch action {
            case .add:
                presenter?.didFailAddFavorite(error: message)
            case .remove:
                presenter?.didFailRemoveFavorite(error: message)
            }
            return
        }

        let referer = actionReferer(for: post)
        Task {
            let actionText: String
            switch action {
            case .add:
                actionText = "收藏"
            case .remove:
                actionText = "取消收藏"
            }
            AppLog.info(.postDetail, "开始\(actionText)帖子，postID=\(post.id)")
            do {
                let response: PostCollectionResponse
                switch action {
                case .add:
                    response = try await collectionSubmitter.addFavorite(postID: post.id, referer: referer)
                case .remove:
                    response = try await collectionSubmitter.removeFavorite(postID: post.id, referer: referer)
                }
                await sessionStore.recordSuccess()
                await MainActor.run {
                    switch action {
                    case .add:
                        presenter?.didAddFavorite(response)
                    case .remove:
                        presenter?.didRemoveFavorite(response)
                    }
                }
            } catch {
                AppLog.error(.postDetail, "\(actionText)帖子失败: \(error.localizedDescription)")
                await MainActor.run {
                    switch action {
                    case .add:
                        presenter?.didFailAddFavorite(error: error.localizedDescription)
                    case .remove:
                        presenter?.didFailRemoveFavorite(error: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func loadPostVote(postID: String, pageURL: URL) {
        voteLoadTask?.cancel()
        let submitter = postVoteSubmitter
        voteLoadTask = Task { [weak self] in
            // 错开详情首屏的渲染高峰，避免投票状态的 WebView 加载挤占资源。
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard Task.isCancelled == false else { return }
            do {
                let vote = try await submitter.loadVote(referer: pageURL)
                guard Task.isCancelled == false, let self else { return }
                self.voteLoadTask = nil
                guard let vote else { return }
                self.presenter?.didLoadPostVote(postID: postID, vote: vote)
            } catch is CancellationError {
                return
            } catch {
                AppLog.debug(.postDetail, "帖子投票状态读取失败: \(error.localizedDescription)")
            }
        }
    }
    private static func loadDetail(
        service: NodeSeekService,
        sessionStore: NodeSeekSessionStore,
        postID: String,
        page: Int
    ) async throws -> DetailLoadOutcome {
        AppLog.info(.postDetail, "详情请求开始，postID=\(postID), page=\(page)")
        let result = try await service.loadPostDetail(postID: postID, page: page)
        switch result {
        case .value(let detail):
            await sessionStore.recordSuccess()
            return .detail(detail)
        case .challenge(let challenge):
            AppLog.warning(.postDetail, "详情请求命中验证，postID=\(postID): \(challenge.logDescription)")
            let message = await sessionStore.recordChallenge(challenge)
            if case .loginRequired = challenge {
                return .loginRequired(message)
            }
            throw MessageError(message: message)
        }
    }

    private func actionReferer(for post: PostSummary) -> URL {
        currentActionPageURL ?? post.url
    }

    private func commentReactionReferer(for post: PostSummary) -> URL {
        NodeSeekSite.postURL(id: post.id, page: 1)
    }

    private static func isCancelledLoad(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

private struct MessageError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}
