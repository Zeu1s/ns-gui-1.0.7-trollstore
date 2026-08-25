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
    let authorID: Int?
    let level: Int?
    let joinDays: Int?
    let avatarURL: URL?
    let viewCount: Int?
    let replyCount: Int?
    let createdAtText: String?
    let lastActivityText: String?
    let lastReplyAuthorName: String?
    let lastReplyAuthorID: Int?
    let nodeName: String?

    init(
        rank: Int,
        title: String,
        postID: Int,
        authorName: String? = nil,
        authorID: Int? = nil,
        level: Int? = nil,
        joinDays: Int? = nil,
        avatarURL: URL? = nil,
        viewCount: Int? = nil,
        replyCount: Int? = nil,
        createdAtText: String? = nil,
        lastActivityText: String? = nil,
        lastReplyAuthorName: String? = nil,
        lastReplyAuthorID: Int? = nil,
        nodeName: String? = nil
    ) {
        self.rank = rank
        self.title = title
        self.postID = postID
        self.authorName = authorName
        self.authorID = authorID
        self.level = level
        self.joinDays = joinDays
        self.avatarURL = avatarURL
        self.viewCount = viewCount
        self.replyCount = replyCount
        self.createdAtText = createdAtText
        self.lastActivityText = lastActivityText
        self.lastReplyAuthorName = lastReplyAuthorName
        self.lastReplyAuthorID = lastReplyAuthorID
        self.nodeName = nodeName
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

    var displayText: String {
        UserCommentPreview.text(from: text)
    }
}

nonisolated enum UserCommentPreview {
    private static let markdownImage = try! NSRegularExpression(
        pattern: "!\\[[^\\]]*\\]\\([^\\)]*\\)",
        options: []
    )
    private static let htmlImage = try! NSRegularExpression(
        pattern: "<img\\b[^>]*>",
        options: [.caseInsensitive]
    )
    private static let htmlBreak = try! NSRegularExpression(
        pattern: "<br\\s*/?>",
        options: [.caseInsensitive]
    )
    private static let htmlTag = try! NSRegularExpression(
        pattern: "<[^>]+>",
        options: []
    )

    nonisolated static func text(from rawText: String) -> String {
        let source = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [markdownImage, htmlImage]
        var result = source

        for pattern in patterns {
            let range = NSRange(result.startIndex..., in: result)
            let matches = pattern.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.removeSubrange(range)
            }
        }

        let breakRange = NSRange(result.startIndex..., in: result)
        result = htmlBreak.stringByReplacingMatches(in: result, options: [], range: breakRange, withTemplate: " ")
        let tagRange = NSRange(result.startIndex..., in: result)
        result = htmlTag.stringByReplacingMatches(in: result, options: [], range: tagRange, withTemplate: "")
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        let textOnly = result
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return textOnly.isEmpty ? "用户发送图片" : textOnly
    }
}

nonisolated struct UserCollectionRecord: Equatable, Sendable {
    let title: String
    let postID: Int
    let rank: Int
    let authorName: String?
    let avatarURL: URL?
    let viewCount: Int?
    let replyCount: Int?
    let lastActivityText: String?

    init(
        title: String,
        postID: Int,
        rank: Int,
        authorName: String? = nil,
        avatarURL: URL? = nil,
        viewCount: Int? = nil,
        replyCount: Int? = nil,
        lastActivityText: String? = nil
    ) {
        self.title = title
        self.postID = postID
        self.rank = rank
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.viewCount = viewCount
        self.replyCount = replyCount
        self.lastActivityText = lastActivityText
    }
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
        if let profileIndex = components.firstIndex(where: { $0 == "space" || $0 == "user" }) {
            let idIndex = components.index(after: profileIndex)
            if idIndex < components.endIndex, let userID = Int(components[idIndex]), userID > 0 {
                return userID
            }
        }
        if let last = components.last,
           last.count > 1,
           last.hasPrefix("n"),
           last.dropFirst().allSatisfy({ $0.isNumber }),
           let userID = Int(last.dropFirst()),
           userID > 0 {
            return userID
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for key in ["uid", "user_id", "userId", "member_id", "memberId", "id"] {
            if let value = queryItems.first(where: { $0.name == key })?.value,
               let userID = Int(value),
               userID > 0 {
                return userID
            }
        }
        return nil
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
