//
//  UserContentRecords.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import Foundation

nonisolated struct UserDiscussionRecord: Equatable, Sendable {
    let rank: Int
    let title: String
    let postID: Int
    let authorName: String?
    let level: Int?
    let avatarURL: URL?
    let viewCount: Int?
    let replyCount: Int?
    let createdAtText: String?
    let lastActivityText: String?

    init(
        rank: Int,
        title: String,
        postID: Int,
        authorName: String? = nil,
        level: Int? = nil,
        avatarURL: URL? = nil,
        viewCount: Int? = nil,
        replyCount: Int? = nil,
        createdAtText: String? = nil,
        lastActivityText: String? = nil
    ) {
        self.rank = rank
        self.title = title
        self.postID = postID
        self.authorName = authorName
        self.level = level
        self.avatarURL = avatarURL
        self.viewCount = viewCount
        self.replyCount = replyCount
        self.createdAtText = createdAtText
        self.lastActivityText = lastActivityText
    }
}

nonisolated struct UserCommentRecord: Equatable, Sendable {
    let postID: Int
    let title: String
    let rank: Int
    let floorID: Int
    let text: String

    var commentPage: Int {
        max(1, (floorID + 9) / 10)
    }

    var anchorID: String {
        "\(floorID)"
    }
}

nonisolated struct UserCollectionRecord: Equatable, Sendable {
    let title: String
    let postID: Int
    let rank: Int
}

extension AccountResponse {
    nonisolated var nodeSeekUID: Int? {
        guard let profileURL else { return nil }
        return NodeSeekUserIDResolver.uid(from: profileURL)
    }
}

enum NodeSeekUserIDResolver {
    nonisolated static func uid(from url: URL) -> Int? {
        let components = url.pathComponents
        guard let spaceIndex = components.firstIndex(of: "space") else { return nil }
        let idIndex = components.index(after: spaceIndex)
        guard idIndex < components.endIndex else { return nil }
        return Int(components[idIndex])
    }
}

enum UserContentPostSummaryFactory {
    nonisolated static func postSummary(id: Int, title: String) -> PostSummary {
        let stringID = "\(id)"
        return PostSummary(
            id: stringID,
            title: title,
            url: NodeSeekSite.postURL(id: stringID, page: 1),
            authorName: "",
            nodeName: nil,
            replyCount: 0,
            lastActivityText: nil
        )
    }
}
