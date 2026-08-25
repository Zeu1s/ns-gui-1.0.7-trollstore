//
//  PostVote.swift
//  nodeseek
//

import Foundation

nonisolated struct PostVoteOption: Equatable, Sendable {
    let id: String
    let title: String
    let voteCount: Int?
    let isSelected: Bool

    init(
        id: String,
        title: String,
        voteCount: Int? = nil,
        isSelected: Bool = false
    ) {
        self.id = id
        self.title = title
        self.voteCount = voteCount
        self.isSelected = isSelected
    }
}

nonisolated struct PostVote: Equatable, Sendable {
    let id: String?
    let title: String
    let allowsMultipleSelection: Bool
    let totalVoteCount: Int?
    let statusText: String?
    let isClosed: Bool
    let canSubmit: Bool
    let isSubmitting: Bool
    let options: [PostVoteOption]

    init(
        id: String? = nil,
        title: String,
        allowsMultipleSelection: Bool = false,
        totalVoteCount: Int? = nil,
        statusText: String? = nil,
        isClosed: Bool = false,
        canSubmit: Bool = false,
        isSubmitting: Bool = false,
        options: [PostVoteOption]
    ) {
        self.id = id
        self.title = title
        self.allowsMultipleSelection = allowsMultipleSelection
        self.totalVoteCount = totalVoteCount
        self.statusText = statusText
        self.isClosed = isClosed
        self.canSubmit = canSubmit
        self.isSubmitting = isSubmitting
        self.options = options
    }

    func updatingSubmitting(_ isSubmitting: Bool) -> PostVote {
        PostVote(
            id: id,
            title: title,
            allowsMultipleSelection: allowsMultipleSelection,
            totalVoteCount: totalVoteCount,
            statusText: statusText,
            isClosed: isClosed,
            canSubmit: canSubmit,
            isSubmitting: isSubmitting,
            options: options
        )
    }
}
