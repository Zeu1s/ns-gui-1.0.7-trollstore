//
//  PostDetailViewController+Table.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import UIKit

extension PostDetailViewController {
    var commentAnchorIndex: [String: Comment] {
        if let cachedCommentAnchorIndex { return cachedCommentAnchorIndex }
        let index = CommentReplyReferenceResolver.commentIndex(among: comments)
        cachedCommentAnchorIndex = index
        return index
    }

    var visiblePagination: PostDetailPagination? {
        guard let pagination, pagination.hasMultiplePages else { return nil }
        return pagination
    }

    private func isCurrentUserComment(_ comment: Comment) -> Bool {
        guard let uid = currentAccountUID,
              let profileURL = comment.authorProfileURL,
              let commentUID = NodeSeekUserInfoStore.userID(from: profileURL) else {
            return false
        }
        return uid == commentUID
    }

    private func threadedCommentRows() -> [(index: Int, depth: Int)] {
        if let cachedThreadedRows { return cachedThreadedRows }
        let result = comments.indices.map { (index: $0, depth: 0) }
        cachedThreadedRows = result
        return result
    }

    var detailRows: [DetailRow] {
        var rows: [DetailRow] = []
        if currentHeaderContent != nil {
            rows.append(.header)
            if shouldShowInitialPageHint {
                rows.append(.entryHint)
            }
            if displayMode == .pageSkeleton || comments.isEmpty == false {
                rows.append(.postRepliesDivider)
            }
        }
        if displayMode == .pageSkeleton {
            rows.append(contentsOf: (0..<skeletonCommentRowCount).map(DetailRow.skeletonComment))
        } else {
            rows.append(contentsOf: threadedCommentRows().map { DetailRow.comment($0.index, $0.depth) })
        }
        return rows
    }

    func pageCompletionScrollRow() -> Int {
        let rows = detailRows
        if let commentRow = rows.firstIndex(where: { row in
            if case .comment = row {
                return true
            }
            return false
        }) {
            return commentRow
        }
        return rows.firstIndex(where: { if case .header = $0 { return true }; return false }) ?? 0
    }

    func fallbackPagination(from pagination: PostDetailPagination?, currentPage: Int) -> PostDetailPagination? {
        guard let pagination else { return nil }
        let normalizedPage = max(1, currentPage)
        let items = pagination.items.map { item in
            PostDetailPageItem(page: item.page, url: item.url, isCurrent: item.page == normalizedPage)
        }
        let pages = items.map(\.page).sorted()
        let previousPage = pages.last { $0 < normalizedPage }
        let nextPage = pages.first { $0 > normalizedPage }
        return PostDetailPagination(
            currentPage: normalizedPage,
            items: items,
            previousPage: previousPage,
            nextPage: nextPage
        )
    }
}

extension PostDetailViewController: ASTableDataSource, ASTableDelegate {
    func handlePostLikeTap(_ header: PostDetailHeaderContent) {
        confirmActionIfNeeded(isAlreadyApplied: header.isLikeClicked, context: .postLike) { [weak self] in
            self?.presenter.didTapPostLike()
        }
    }

    func handleCommentLikeTap(_ comment: Comment) {
        confirmActionIfNeeded(isAlreadyApplied: comment.isLikeClicked, context: .commentLike) { [weak self] in
            self?.presenter.didTapCommentLike(comment)
        }
    }

    func handlePostChickenLegTap(_ header: PostDetailHeaderContent) {
        confirmActionIfNeeded(isAlreadyApplied: header.isChickenLegClicked, context: .postChickenLeg) { [weak self] in
            self?.presenter.didTapPostChickenLeg()
        }
    }

    func handleCommentChickenLegTap(_ comment: Comment) {
        confirmActionIfNeeded(isAlreadyApplied: comment.isChickenLegClicked, context: .commentChickenLeg) { [weak self] in
            self?.presenter.didTapCommentChickenLeg(comment)
        }
    }

    func handlePostOpposeTap(_ header: PostDetailHeaderContent) {
        confirmActionIfNeeded(isAlreadyApplied: header.isOpposeClicked, context: .postOppose) { [weak self] in
            self?.presenter.didTapPostOppose()
        }
    }

    func handleCommentOpposeTap(_ comment: Comment) {
        confirmActionIfNeeded(isAlreadyApplied: comment.isOpposeClicked, context: .commentOppose) { [weak self] in
            self?.presenter.didTapCommentOppose(comment)
        }
    }

    private func confirmActionIfNeeded(
        isAlreadyApplied: Bool,
        context: PostDetailActionConfirmationContext,
        onConfirm: @escaping @MainActor () -> Void
    ) {
        guard isAlreadyApplied == false else {
            onConfirm()
            return
        }

        actionConfirmationPresenter(self, context, onConfirm)
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        if displayMode == .skeleton {
            return 1 + skeletonCommentRowCount
        }
        return detailRows.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        if displayMode == .skeleton {
            let kind: PostDetailSkeletonCellNode.Kind = indexPath.row == 0 ? .header : .comment
            return {
                PostDetailSkeletonCellNode(kind: kind)
            }
        }

        let rows = detailRows
        guard rows.indices.contains(indexPath.row) else {
            return { ASCellNode() }
        }

        switch rows[indexPath.row] {
        case .header:
            guard let header = currentHeaderContent else {
                return { ASCellNode() }
            }
            let renderedContent = headerRenderedContent
            let imageSizeProvider = makeCurrentImageSizeProvider()
            return { [weak self] in
                PostBodyCellNode(
                    content: header,
                    renderedContent: renderedContent,
                    onImageTapped: { imageURLs, initialIndex in
                        self?.presentPhotoBrowser(imageURLs: imageURLs, initialIndex: initialIndex)
                    },
                    onImageLongPressed: { imageURL in
                        self?.presentImageActions(for: imageURL)
                    },
                    onLinkTapped: { url in
                        self?.handleContentLinkTap(url)
                    },
                    onSignatureLinkCandidatesTapped: { candidates in
                        self?.handleSignatureLinkCandidatesTap(candidates)
                    },
                    onAuthorTapped: { url in
                        self?.openUserInfo(profileURL: url)
                    },
                    onLikeTapped: {
                        self?.handlePostLikeTap(header)
                    },
                    onChickenLegTapped: {
                        self?.handlePostChickenLegTap(header)
                    },
                    onOpposeTapped: {
                        self?.handlePostOpposeTap(header)
                    },
                    onFavoriteTapped: {
                        self?.presenter.didTapFavorite()
                    },
                    onVoteSubmitted: { optionIDs in
                        self?.presenter.didTapVote(optionIDs: optionIDs)
                    },
                    onReplyTapped: {
                        self?.handleReply(toPostHeader: header)
                    },
                    onCommentTapped: {
                        self?.presentCommentEditor()
                    },
                    onEditTapped: {
                        self?.presentDiscussionEditor()
                    },
                    onContentCopyTapped: { content in
                        self?.presentPostBodyCopySheet(for: content)
                    },
                    showsReplyActions: self?.showsReplyEntry == true,
                    showsDiscussionEditAction: self?.showsDiscussionEditAction == true,
                    onTextLayoutInvalidated: {
                        self?.scheduleAttachmentLayoutRefresh()
                    },
                    imageSizeProvider: imageSizeProvider,
                    onImageSizeResolved: { url, size in
                        self?.cacheDetailImageSize(size, for: url)
                    },
                    onImageHeightReduced: {
                        self?.scheduleHeaderReload()
                    },
                    selectedMagicTabIndex: { key in
                        self?.magicTabSelectedIndexes[key]
                    },
                    onMagicTabSelected: { key, index in
                        self?.magicTabSelectedIndexes[key] = index
                    }
                )
            }
        case .entryHint:
            let page = initialPage
            return { [weak self] in
                PostDetailEntryHintCellNode(page: page) {
                    self?.openFullPostFromEntryHint()
                }
            }
        case .postRepliesDivider:
            return {
                PostRepliesDividerCellNode()
            }
        case .skeletonComment(_):
            return {
                PostDetailSkeletonCellNode(kind: .comment)
            }
        case .comment(let commentIndex, let depth):
            guard comments.indices.contains(commentIndex) else {
                return { ASCellNode() }
            }

            let comment = comments[commentIndex]
            let renderedBody = commentRenderedCache[comment.id]
            let replyReference = CommentReplyReferenceResolver.reference(for: comment, among: comments, index: commentAnchorIndex)
            let imageSizeProvider = makeCurrentImageSizeProvider()
            return { [weak self] in
                CommentCellNode(
                    comment: comment,
                    renderedBody: renderedBody,
                    replyReference: replyReference,
                    depth: depth,
                    showsEditAction: self?.isCurrentUserComment(comment) == true,
                    onEditTapped: { comment in
                        self?.handleEditComment(comment)
                    },
                    onImageTapped: { imageURLs, initialIndex in
                        self?.presentPhotoBrowser(imageURLs: imageURLs, initialIndex: initialIndex)
                    },
                    onImageLongPressed: { imageURL in
                        self?.presentImageActions(for: imageURL)
                    },
                    onLinkTapped: { url in
                        self?.handleContentLinkTap(url)
                    },
                    onSignatureLinkCandidatesTapped: { candidates in
                        self?.handleSignatureLinkCandidatesTap(candidates)
                    },
                    onAuthorTapped: { url in
                        self?.openUserInfo(profileURL: url)
                    },
                    onAuthorCopyTapped: { comment in
                        self?.presentCommentCopySheet(for: comment)
                    },
                    onLikeTapped: { comment in
                        self?.handleCommentLikeTap(comment)
                    },
                    onChickenLegTapped: { comment in
                        self?.handleCommentChickenLegTap(comment)
                    },
                    onOpposeTapped: { comment in
                        self?.handleCommentOpposeTap(comment)
                    },
                    onReplyTapped: { comment in
                        self?.handleReply(to: comment)
                    },
                    onQuoteTapped: { comment in
                        self?.handleQuote(comment)
                    },
                    onReplyReferenceTapped: { referencedComment in
                        let anchorID = referencedComment.anchorID
                            ?? referencedComment.floorText?.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                        guard let anchorID,
                              anchorID.isEmpty == false else {
                            return
                        }
                        self?.scrollToCurrentPageAnchor(anchorID)
                    },
                    onTextLayoutInvalidated: {
                        self?.scheduleAttachmentLayoutRefresh()
                    },
                    imageSizeProvider: imageSizeProvider,
                    onImageSizeResolved: { url, size in
                        self?.cacheDetailImageSize(size, for: url)
                    },
                    onImageHeightReduced: {
                        self?.scheduleCommentReload(commentID: comment.id)
                    }
                )
            }
        }
    }

    private func makeCurrentImageSizeProvider() -> (URL) -> CGSize? {
        Self.makeImageSizeProvider(from: detailImageSizeCache)
    }

    private static func makeImageSizeProvider(from cache: [URL: CGSize]) -> (URL) -> CGSize? {
        { url in
            guard let resolvedURL = ImageURLResolver.resolve(url),
                  let size = cache[resolvedURL],
                  size.width > 0,
                  size.height > 0 else {
                return nil
            }
            return size
        }
    }

    func tableNode(_ tableNode: ASTableNode, willDisplayRowWith node: ASCellNode) {
        guard displayMode == .content else { return }
        guard let indexPath = tableNode.indexPath(for: node) else { return }
        let rows = detailRows
        guard rows.indices.contains(indexPath.row),
              case .comment(let commentIndex, _) = rows[indexPath.row] else { return }
        guard comments.indices.contains(commentIndex) else { return }
        scheduleCommentRenderIfNeeded(for: comments[commentIndex])
    }

    func shouldBatchFetch(for tableNode: ASTableNode) -> Bool {
        // Texture 的预取在首屏尚未被用户浏览时也会触发，快速进出详情会累积无效请求。
        false
    }

    func tableNode(_ tableNode: ASTableNode, willBeginBatchFetchWith context: ASBatchContext) {
        context.completeBatchFetching(true)
    }
    private func canRequestCommentBatchFetch() -> Bool {
        guard displayMode == .content else { return false }
        guard pagination?.nextPage != nil else { return false }
        guard !comments.isEmpty else { return false }
        guard lastBatchFetchRequestedCommentCount != comments.count else { return false }
        return true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        handleFloatingControlsScrollActivity(scrollView)
        updateNavigationAuthorVisibility(contentOffsetY: scrollView.contentOffset.y, animated: true)
        requestNextCommentPageIfNeeded(whileScrolling: scrollView)
    }

    private func requestNextCommentPageIfNeeded(whileScrolling scrollView: UIScrollView) {
        guard canRequestCommentBatchFetch(), scrollView.contentOffset.y > 0 else { return }
        guard Date() >= nextAutomaticCommentPageRequestDate else { return }
        let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height - scrollView.adjustedContentInset.bottom
        let remainingDistance = scrollView.contentSize.height - visibleBottom
        // 距底约一屏即开始预加载下一页，翻页衔接无停顿。
        guard remainingDistance <= 620 else { return }

        lastBatchFetchRequestedCommentCount = comments.count
        // 快速惯性滚动时，等本页插入后的布局稳定再请求下一页，避免请求、节点创建和图片
        // 排版同时堆积在主线程。
        nextAutomaticCommentPageRequestDate = Date().addingTimeInterval(0.55)
        AppLog.info(.postDetail, "用户接近评论底部，加载下一页: comments=\(comments.count), remaining=\(Int(remainingDistance))")
        presenter.didApproachCommentEnd()
    }
}
