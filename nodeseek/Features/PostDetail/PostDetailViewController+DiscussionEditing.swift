//
//  PostDetailViewController+DiscussionEditing.swift
//  nodeseek
//

import UIKit

extension PostDetailViewController {
    func presentDiscussionEditorIfNeeded() {
        guard shouldOpenDiscussionEditorAfterInitialRender,
              hasPresentedDiscussionEditor == false,
              hasRenderedDetailContent,
              viewIfLoaded?.window != nil,
              let header = currentHeaderContent else {
            return
        }

        let post = PostSummary(
            id: header.postID,
            title: header.title,
            url: sourcePostURL ?? NodeSeekSite.postURL(id: header.postID, page: currentPage),
            authorName: header.authorName,
            nodeName: nil,
            replyCount: 0,
            lastActivityText: header.metadataText,
            avatarURL: header.avatarURL,
            authorProfileURL: header.authorProfileURL
        )
        DispatchQueue.main.async { [weak self, post] in
            guard let self,
                  self.navigationController?.topViewController === self else {
                return
            }
            self.hasPresentedDiscussionEditor = true
            self.navigationController?.pushViewController(
                DiscussionEditViewController(post: post) { [weak self] in
                    self?.presenter.refreshInitialPage()
                },
                animated: true
            )
        }
    }

    func presentDiscussionEditor() {
        guard hasRenderedDetailContent,
              viewIfLoaded?.window != nil,
              let header = currentHeaderContent else {
            return
        }

        let post = PostSummary(
            id: header.postID,
            title: header.title,
            url: sourcePostURL ?? NodeSeekSite.postURL(id: header.postID, page: currentPage),
            authorName: header.authorName,
            nodeName: nil,
            replyCount: 0,
            lastActivityText: header.metadataText,
            avatarURL: header.avatarURL,
            authorProfileURL: header.authorProfileURL
        )
        DispatchQueue.main.async { [weak self, post] in
            guard let self,
                  self.navigationController?.topViewController === self,
                  self.presentedViewController == nil else {
                return
            }
            self.navigationController?.pushViewController(
                DiscussionEditViewController(post: post) { [weak self] in
                    self?.presenter.refreshInitialPage()
                },
                animated: true
            )
        }
    }
}
