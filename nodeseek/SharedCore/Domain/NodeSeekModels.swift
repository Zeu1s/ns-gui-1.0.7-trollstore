//
//  NodeSeekModels.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

nonisolated struct AccountNotification: Equatable, Sendable {
    let url: URL
    let iconColorCSS: String?
}

nonisolated struct AccountResponse: Equatable, Sendable {
    let displayName: String
    let isLoggedIn: Bool
    let avatarURL: URL?
    let profileURL: URL?
    let stats: [String]
    let notification: AccountNotification?

    init(
        displayName: String,
        isLoggedIn: Bool,
        avatarURL: URL? = nil,
        profileURL: URL? = nil,
        stats: [String] = [],
        notification: AccountNotification? = nil
    ) {
        self.displayName = displayName
        self.isLoggedIn = isLoggedIn
        self.avatarURL = avatarURL
        self.profileURL = profileURL
        self.stats = stats
        self.notification = notification
    }
}

nonisolated struct PostSummary: Equatable, Sendable {
    let id: String
    let title: String
    let url: URL
    let authorName: String
    let nodeName: String?
    let replyCount: Int
    let viewCount: Int
    let createdAtText: String?
    let lastActivityText: String?
    let isPinned: Bool
    let isLocked: Bool
    let requiredReadingLevel: Int?
    let avatarURL: URL?
    let authorProfileURL: URL?
    let authorBadgeTexts: [String]

    init(
        id: String,
        title: String,
        url: URL,
        authorName: String,
        nodeName: String?,
        replyCount: Int,
        viewCount: Int = 0,
        createdAtText: String? = nil,
        lastActivityText: String?,
        isPinned: Bool = false,
        isLocked: Bool = false,
        requiredReadingLevel: Int? = nil,
        avatarURL: URL? = nil,
        authorProfileURL: URL? = nil,
        authorBadgeTexts: [String] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.authorName = authorName
        self.nodeName = nodeName
        self.replyCount = replyCount
        self.viewCount = viewCount
        self.createdAtText = createdAtText
        self.lastActivityText = lastActivityText
        self.isPinned = isPinned
        self.isLocked = isLocked
        self.requiredReadingLevel = requiredReadingLevel
        self.avatarURL = avatarURL
        self.authorProfileURL = authorProfileURL
        self.authorBadgeTexts = authorBadgeTexts
    }
}

nonisolated struct PostDetailPageItem: Equatable, Sendable {
    let page: Int
    let url: URL?
    let isCurrent: Bool
}

nonisolated struct PostDetailPagination: Equatable, Sendable {
    let currentPage: Int
    let items: [PostDetailPageItem]
    let previousPage: Int?
    let nextPage: Int?

    var hasMultiplePages: Bool {
        items.count > 1 || previousPage != nil || nextPage != nil
    }
}

nonisolated struct PostDetail: Equatable, Sendable {
    let id: String
    let title: String
    let requiredReadingLevel: Int?
    let authorName: String
    let avatarURL: URL?
    let authorProfileURL: URL?
    let authorBadgeTexts: [String]
    let metadataText: String?
    let contentHTML: String
    let signatureHTML: String?
    /// 详情页运行时 postData.views（内联脚本提取），用于列表页浏览数回填。
    let viewCountFromDetail: Int?
    /// 详情页板块中文名（postData.categoryWord）。
    let categoryWord: String?
    let likeCount: Int?
    let isLikeClicked: Bool
    let chickenLegCount: Int?
    let isChickenLegClicked: Bool
    let opposeCount: Int?
    let isOpposeClicked: Bool
    let favoriteCount: Int?
    let isFavoriteCollected: Bool
    let isRestricted: Bool
    let vote: PostVote?
    let comments: [Comment]
    let page: Int
    let pagination: PostDetailPagination?
    let isLastPage: Bool

    init(
        id: String,
        title: String,
        requiredReadingLevel: Int? = nil,
        authorName: String,
        avatarURL: URL?,
        authorProfileURL: URL? = nil,
        authorBadgeTexts: [String] = [],
        metadataText: String?,
        contentHTML: String,
        signatureHTML: String? = nil,
        viewCountFromDetail: Int? = nil,
        categoryWord: String? = nil,
        likeCount: Int? = nil,
        isLikeClicked: Bool = false,
        chickenLegCount: Int? = nil,
        isChickenLegClicked: Bool = false,
        opposeCount: Int? = nil,
        isOpposeClicked: Bool = false,
        favoriteCount: Int? = nil,
        isFavoriteCollected: Bool = false,
        isRestricted: Bool = false,
        vote: PostVote? = nil,
        comments: [Comment],
        page: Int = 1,
        pagination: PostDetailPagination? = nil,
        isLastPage: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.requiredReadingLevel = requiredReadingLevel
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.authorProfileURL = authorProfileURL
        self.authorBadgeTexts = authorBadgeTexts
        self.metadataText = metadataText
        self.contentHTML = contentHTML
        self.signatureHTML = signatureHTML
        self.viewCountFromDetail = viewCountFromDetail
        self.categoryWord = categoryWord
        self.likeCount = likeCount
        self.isLikeClicked = isLikeClicked
        self.chickenLegCount = chickenLegCount
        self.isChickenLegClicked = isChickenLegClicked
        self.opposeCount = opposeCount
        self.isOpposeClicked = isOpposeClicked
        self.favoriteCount = favoriteCount
        self.isFavoriteCollected = isFavoriteCollected
        self.isRestricted = isRestricted
        self.vote = vote
        self.comments = comments
        self.page = max(1, page)
        self.pagination = pagination
        self.isLastPage = isLastPage ?? (pagination?.nextPage == nil)
    }

    func updatingVote(_ vote: PostVote?) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            authorBadgeTexts: authorBadgeTexts,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            vote: vote,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }
    func updatingFavoriteState(count: Int?, isCollected: Bool) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: count,
            isFavoriteCollected: isCollected,
            isRestricted: isRestricted,
            vote: vote,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingPostLikeState(count: Int?, isClicked: Bool) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            likeCount: count,
            isLikeClicked: isClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            vote: vote,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingCommentLikeState(commentID: String, count: Int?, isClicked: Bool) -> PostDetail {
        let nextComments = comments.map { comment in
            comment.id == commentID
                ? comment.updatingLikeReaction(count: count, isClicked: isClicked)
                : comment
        }

        return PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            vote: vote,
            comments: nextComments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingPostChickenLegState(count: Int?, isClicked: Bool) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: count,
            isChickenLegClicked: isClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            vote: vote,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingCommentChickenLegState(commentID: String, count: Int?, isClicked: Bool) -> PostDetail {
        let nextComments = comments.map { comment in
            comment.id == commentID
                ? comment.updatingChickenLegReaction(count: count, isClicked: isClicked)
                : comment
        }

        return PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            vote: vote,
            comments: nextComments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingPostOpposeState(count: Int?, isClicked: Bool) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: count,
            isOpposeClicked: isClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            vote: vote,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingCommentOpposeState(commentID: String, count: Int?, isClicked: Bool) -> PostDetail {
        let nextComments = comments.map { comment in
            comment.id == commentID
                ? comment.updatingOpposeReaction(count: count, isClicked: isClicked)
                : comment
        }

        return PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            vote: vote,
            comments: nextComments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }
}

/// 站点的编辑时间只在楼层真被编辑过时才渲染 `span.date-updated`，
/// 其 `title` 是英文 `Edited 2026-09-19 15:41:23 by qa33794530`，
/// 中文界面下也不翻译，所以这里只按固定形状取值，不依赖前缀。
nonisolated enum NodeSeekEditedAt {
    /// → `2026-09-19 15:41`（去掉秒）；形状不对返回 nil。
    static func timestamp(fromTitle title: String?) -> String? {
        guard var value = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else { return nil }
        if let byRange = value.range(of: " by ", options: .caseInsensitive) {
            value = String(value[..<byRange.lowerBound])
        }
        if let prefixRange = value.range(of: "Edited", options: .caseInsensitive) {
            value = String(value[prefixRange.upperBound...])
        }
        value = value
            .replacingOccurrences(of: "T", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 16, value.contains("-"), value.contains(":") else { return nil }
        return String(value.prefix(16))
    }

    /// → `qa33794530`；没有 by 段时返回 nil。
    static func editor(fromTitle title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              let byRange = title.range(of: " by ", options: .caseInsensitive) else {
            return nil
        }
        let name = String(title[byRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

nonisolated struct Comment: Equatable, Sendable {
    let id: String
    let anchorID: String?
    let authorName: String
    let isPoster: Bool
    let avatarURL: URL?
    let authorProfileURL: URL?
    let authorBadgeTexts: [String]
    let floorText: String?
    let createdAtText: String?
    let createdAtTitleText: String?
    /// 站点 `span.date-updated` 的文本，形如 `edited 1day ago`；未被编辑时为 nil。
    let editedText: String?
    /// 同上的 `title`，形如 `Edited 2026-09-19 15:41:23 by qa33794530`。
    let editedTitleText: String?
    let contentHTML: String
    let signatureHTML: String?
    let isHot: Bool
    let likeCount: Int?
    let isLikeClicked: Bool
    let chickenLegCount: Int?
    let isChickenLegClicked: Bool
    let opposeCount: Int?
    let isOpposeClicked: Bool

    init(
        id: String,
        anchorID: String? = nil,
        authorName: String,
        isPoster: Bool = false,
        avatarURL: URL?,
        authorProfileURL: URL? = nil,
        authorBadgeTexts: [String] = [],
        floorText: String?,
        createdAtText: String?,
        createdAtTitleText: String? = nil,
        editedText: String? = nil,
        editedTitleText: String? = nil,
        contentHTML: String,
        signatureHTML: String? = nil,
        isHot: Bool = false,
        likeCount: Int? = nil,
        isLikeClicked: Bool = false,
        chickenLegCount: Int? = nil,
        isChickenLegClicked: Bool = false,
        opposeCount: Int? = nil,
        isOpposeClicked: Bool = false
    ) {
        self.id = id
        self.anchorID = anchorID
        self.authorName = authorName
        self.isPoster = isPoster
        self.avatarURL = avatarURL
        self.authorProfileURL = authorProfileURL
        self.authorBadgeTexts = authorBadgeTexts
        self.floorText = floorText
        self.createdAtText = createdAtText
        self.createdAtTitleText = createdAtTitleText
        self.editedText = editedText
        self.editedTitleText = editedTitleText
        self.contentHTML = contentHTML
        self.signatureHTML = signatureHTML
        self.isHot = isHot
        self.likeCount = likeCount
        self.isLikeClicked = isLikeClicked
        self.chickenLegCount = chickenLegCount
        self.isChickenLegClicked = isChickenLegClicked
        self.opposeCount = opposeCount
        self.isOpposeClicked = isOpposeClicked
    }

    /// 站点的编辑时间，来自 `span.date-updated`。
    var editedAtText: String? { NodeSeekEditedAt.timestamp(fromTitle: editedTitleText) }
    /// 编辑者不是本帖作者时（比如版主改贴）需要区分出来。
    var editedByName: String? { NodeSeekEditedAt.editor(fromTitle: editedTitleText) }

    func updatingLikeReaction(count: Int?, isClicked: Bool) -> Comment {
        Comment(
            id: id,
            anchorID: anchorID,
            authorName: authorName,
            isPoster: isPoster,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            authorBadgeTexts: authorBadgeTexts,
            floorText: floorText,
            createdAtText: createdAtText,
            createdAtTitleText: createdAtTitleText,
            editedText: editedText,
            editedTitleText: editedTitleText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            isHot: isHot,
            likeCount: count,
            isLikeClicked: isClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked
        )
    }

    func updatingChickenLegReaction(count: Int?, isClicked: Bool) -> Comment {
        Comment(
            id: id,
            anchorID: anchorID,
            authorName: authorName,
            isPoster: isPoster,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            authorBadgeTexts: authorBadgeTexts,
            floorText: floorText,
            createdAtText: createdAtText,
            createdAtTitleText: createdAtTitleText,
            editedText: editedText,
            editedTitleText: editedTitleText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            isHot: isHot,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: count,
            isChickenLegClicked: isClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked
        )
    }

    func updatingOpposeReaction(count: Int?, isClicked: Bool) -> Comment {
        Comment(
            id: id,
            anchorID: anchorID,
            authorName: authorName,
            isPoster: isPoster,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            authorBadgeTexts: authorBadgeTexts,
            floorText: floorText,
            createdAtText: createdAtText,
            createdAtTitleText: createdAtTitleText,
            editedText: editedText,
            editedTitleText: editedTitleText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            isHot: isHot,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: count,
            isOpposeClicked: isClicked
        )
    }
}

nonisolated struct CheckInState: Equatable, Sendable {
    let isCheckedIn: Bool
    let message: String
    let actionURL: URL?
    let hiddenFields: [String: String]
}

nonisolated struct UserSummary: Equatable, Sendable {
    let displayName: String
    let isLoggedIn: Bool
}

nonisolated enum AuthorDisplayPolicy {
    static func displayName(from rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "未知用户" else {
            return nil
        }

        return name
    }

    static func isDisplayable(_ rawName: String) -> Bool {
        displayName(from: rawName) != nil
    }
}
