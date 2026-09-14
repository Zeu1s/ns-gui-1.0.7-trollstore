//
//  PostDetailContract.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import UIKit

// MARK: - View Protocol (Presenter -> View)
protocol PostDetailViewProtocol: AnyObject {
    func showLoading()
    func showLoadingMoreComments()
    func hideLoadingMoreComments()
    func hideLoading()
    func showError(message: String)
    func showPostUnavailable(message: String)
    func showToast(message: String)
    func setReplySubmitting(_ isSubmitting: Bool)
    func setFavoriteSubmitting(_ isSubmitting: Bool)
    func finishReplySubmission()
    func render(detail: PostDetail)
    func refreshCurrentCommentPage(detail: PostDetail)
    func focusComment(anchorID: String)
    func scrollToLatestComment()
    func appendCommentPage(detail: PostDetail)
    func updatePostBody(detail: PostDetail)
    func updateCommentLike(commentID: String, count: Int?, isClicked: Bool)
    func updateCommentChickenLeg(commentID: String, count: Int?, isClicked: Bool)
    func updateCommentOppose(commentID: String, count: Int?, isClicked: Bool)
    func renderLoginRequired(message: String)
    /// 当前用户在本帖的回复分布（pages: 已加载页中含我回复的页码；
    /// latestAnchorID: 最新一条我的回复锚点，用于直达定位）。
    func updateMyReplies(pages: [Int], latestAnchorID: String?)
}

// MARK: - Presenter Protocol (View -> Presenter)
protocol PostDetailPresenterProtocol: AnyObject {
    func viewDidLoad()
    func cancelPendingLoad()
    func refreshInitialPage()
    func didTapLogin()
    func didApproachCommentEnd()
    func didTapRefreshCommentsAtEnd()
    func didRequestLatestComment()
    func didTapSendReply(content: String)
    func didTapFavorite()
    func didTapVote(optionIDs: [String])
    func didTapPostLike()
    func didTapPostChickenLeg()
    func didTapPostOppose()
    func didTapCommentLike(_ comment: Comment)
    func didTapCommentChickenLeg(_ comment: Comment)
    func didTapCommentOppose(_ comment: Comment)
    /// 用户在"我的回复"列表中选择某条，请求加载对应页并定位。
    func didTapMyReply(page: Int, anchorID: String?)
}

// 详情页的“跳至最后一条评论”是可选增强能力。为既有测试桩和轻量实现提供默认行为，
// 避免协议扩展后把不参与该导航的调用方也变成编译错误。
extension PostDetailViewProtocol {
    func scrollToLatestComment() {}
    func updateMyReplies(pages: [Int], latestAnchorID: String?) {}
}
}

extension PostDetailPresenterProtocol {
    func didRequestLatestComment() {}
    func cancelPendingLoad() {}
    func didTapVote(optionIDs: [String]) {}
}

// MARK: - Interactor Input (Presenter -> Interactor)
protocol PostDetailInteractorInput: AnyObject {
    func loadPostDetail()
    func loadPostDetail(page: Int)
    func cancelPendingLoad()
    func submitReply(content: String)
    func addFavorite()
    func submitVote(optionIDs: [String])
    func removeFavorite()
    func addPostLike()
    func addCommentLike(commentID: String)
    func addPostChickenLeg()
    func addCommentChickenLeg(commentID: String)
    func addPostOppose()
    func addCommentOppose(commentID: String)
}

extension PostDetailInteractorInput {
    func cancelPendingLoad() {}
    func submitVote(optionIDs: [String]) {}
}

// MARK: - Interactor Output (Interactor -> Presenter)
protocol PostDetailInteractorOutput: AnyObject {
    func didLoadPostDetail(_ response: PostDetailResponse)
    func didLoadPostVote(postID: String, vote: PostVote)
    func didRequireLogin(message: String)
    func didFailLoadPostDetail(error: String)
    func didCancelLoadPostDetail()
    func didSubmitReply(_ response: PostDetailSubmitReplyResponse)
    func didFailSubmitReply(error: String)
    func didSubmitPostVote(_ response: PostVoteSubmissionResponse)
    func didFailSubmitPostVote(error: String)
    func didAddFavorite(_ response: PostCollectionResponse)
    func didFailAddFavorite(error: String)
    func didRemoveFavorite(_ response: PostCollectionResponse)
    func didFailRemoveFavorite(error: String)
    func didAddPostLike(_ response: PostUpvoteResponse)
    func didFailAddPostLike(error: String)
    func didAddCommentLike(commentID: String, response: CommentUpvoteResponse)
    func didFailAddCommentLike(commentID: String, error: String)
    func didAddPostChickenLeg(_ response: PostChickenLegResponse)
    func didFailAddPostChickenLeg(error: String)
    func didAddCommentChickenLeg(commentID: String, response: CommentChickenLegResponse)
    func didFailAddCommentChickenLeg(commentID: String, error: String)
    func didAddPostOppose(_ response: PostDislikeResponse)
    func didFailAddPostOppose(error: String)
    func didAddCommentOppose(commentID: String, response: CommentDislikeResponse)
    func didFailAddCommentOppose(commentID: String, error: String)
}

extension PostDetailInteractorOutput {
    func didLoadPostVote(postID: String, vote: PostVote) {}
    func didSubmitPostVote(_ response: PostVoteSubmissionResponse) {}
    func didFailSubmitPostVote(error: String) {}
}

// MARK: - Router Protocol (Presenter -> Router)
protocol PostDetailRouterProtocol: AnyObject {
    func navigateToLogin(onClose: @escaping @MainActor () -> Void)
}
