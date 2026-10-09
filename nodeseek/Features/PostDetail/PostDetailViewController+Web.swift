//
//  PostDetailViewController+Web.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import SafariServices
import UIKit

extension PostDetailViewController {
    @objc
    func openInBrowserTapped() {
        guard let targetURL = resolvedDetailURL() else {
            showError(message: "当前帖子链接无效，暂时无法打开。")
            return
        }

        openHTTPURLInSelectedBrowser(targetURL)
    }

    func shareCurrentPost(sourceItem: UIBarButtonItem?) {
        guard let targetURL = resolvedDetailURL() else {
            showError(message: "当前帖子链接无效，暂时无法分享。")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [targetURL], applicationActivities: nil)
        activityViewController.popoverPresentationController?.barButtonItem = sourceItem
        present(activityViewController, animated: true)
    }

    func copyCurrentPostLink() {
        guard let targetURL = resolvedDetailURL() else {
            showError(message: "当前帖子链接无效，暂时无法复制。")
            return
        }

        pasteboardStringWriter(targetURL.absoluteString)
        showToast(message: "已复制链接")
    }

    func handleContentLinkTap(_ url: URL) {
        if handleLoadedCommentAnchorIfNeeded(for: url) {
            return
        }

        guard let destination = PostDetailLinkResolver.destination(
            for: url,
            baseURL: baseURL,
            currentPostID: currentHeaderContent?.postID,
            currentPage: currentPage
        ) else { return }

        switch destination {
        case .currentPageAnchor(let anchorID):
            scrollToCurrentPageAnchor(anchorID)
        case .nativePost(let postID, let page, let url):
            let post = PostSummary(
                id: postID,
                title: "帖子 #\(postID)",
                url: url,
                authorName: "",
                nodeName: nil,
                replyCount: 0,
                lastActivityText: nil
            )
            let viewController = PostDetailRouter.createModule(
                post: post,
                page: page,
                initialAnchorID: NodeSeekPostRouteResolver.route(for: url, baseURL: baseURL)?.anchorID
            )
            showDetailDestination(viewController)
        case .nativePrivateMessage(let participantID):
            showDetailDestination(
                PrivateMessageViewController(
                    participantID: participantID,
                    participantName: "私信"
                )
            )
        case .userProfile(let url):
            openUserInfo(profileURL: url)
        case .web(let url):
            let webViewController = NodeSeekWebViewController(url: url)
            showDetailDestination(webViewController)
        case .safari(let url):
            openHTTPURLInSelectedBrowser(url)
        case .externalApp(let url):
            AppLog.info(.runtime, "请求打开外部应用: \(url.absoluteString)")
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                guard success == false else { return }
                DispatchQueue.main.async {
                    self?.showError(message: "无法打开这个链接。")
                }
            }
        }
    }

    private func openHTTPURLInSelectedBrowser(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            AppLog.warning(.runtime, "浏览器打开请求被忽略，非 HTTP(S) 链接: \(url.absoluteString)")
            return
        }

        let mode = BrowserOpenMode.current
        AppLog.info(.runtime, "使用 \(mode.title) 打开链接: \(url.absoluteString)")
        switch mode {
        case .inAppSafari:
            present(SFSafariViewController(url: url), animated: true)
        case .safari:
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                guard success == false else { return }
                DispatchQueue.main.async {
                    self?.showError(message: "无法使用 Safari 打开这个链接。")
                }
            }
        case .chrome:
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                showError(message: "当前链接无效，暂时无法使用 Chrome 打开。")
                return
            }
            components.scheme = scheme == "https" ? "googlechromes" : "googlechrome"
            guard let chromeURL = components.url else {
                showError(message: "当前链接无效，暂时无法使用 Chrome 打开。")
                return
            }
            UIApplication.shared.open(chromeURL, options: [:]) { [weak self] success in
                guard success == false else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    AppLog.warning(.runtime, "未检测到 Chrome，回退 Safari: \(url.absoluteString)")
                    self.showToast(message: "未检测到 Chrome，已使用 Safari 打开")
                    self.present(SFSafariViewController(url: url), animated: true)
                }
            }
        }
    }

    func handleSignatureLinkCandidatesTap(_ candidates: [DetailLinkCandidate]) {
        let uniqueCandidates = Self.uniqueLinkCandidates(candidates)
        guard uniqueCandidates.isEmpty == false else { return }

        let sheet = LinkSelectionSheetViewController(
            candidates: uniqueCandidates,
            onSelect: { [weak self] url in
                self?.handleContentLinkTap(url)
            }
        )
        present(sheet, animated: true)
    }

    static func uniqueLinkCandidates(_ candidates: [DetailLinkCandidate]) -> [DetailLinkCandidate] {
        var uniqueCandidates: [DetailLinkCandidate] = []
        for candidate in candidates {
            guard uniqueCandidates.contains(candidate) == false else { continue }
            uniqueCandidates.append(candidate)
        }
        return uniqueCandidates
    }

    func handleLoadedCommentAnchorIfNeeded(for url: URL) -> Bool {
        guard let anchorID = currentPostCommentAnchorID(from: url),
              anchorID != "0",
              let comment = loadedComment(matchingAnchorID: anchorID),
              let indexPath = indexPathForLoadedComment(comment) else {
            return false
        }

        if isLoadedCommentVisible(anchorID: anchorID, indexPath: indexPath) {
            scrollToCurrentPageAnchor(anchorID)
            return true
        }

        presentLoadedCommentPreview(comment: comment, anchorID: anchorID)
        return true
    }

    private func currentPostCommentAnchorID(from url: URL) -> String? {
        guard let resolvedURL = URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL,
              isNodeSeekHost(resolvedURL),
              let anchorID = normalizedAnchorID(from: resolvedURL),
              anchorID.isEmpty == false else {
            return nil
        }

        if resolvedURL.path.isEmpty || resolvedURL.path == "/" {
            return anchorID
        }

        guard let currentPostID = currentHeaderContent?.postID,
              let route = NodeSeekPostRouteResolver.route(for: resolvedURL, baseURL: baseURL),
              route.postID == currentPostID else {
            return nil
        }
        return route.anchorID
    }

    private func loadedComment(matchingAnchorID anchorID: String) -> Comment? {
        let normalizedTarget = normalizedAnchorText(anchorID)
        guard normalizedTarget.isEmpty == false else { return nil }
        return comments.first { comment in
            normalizedAnchorText(comment.anchorID) == normalizedTarget
                || normalizedAnchorText(comment.floorText) == normalizedTarget
        }
    }

    private func indexPathForLoadedComment(_ comment: Comment) -> IndexPath? {
        guard let commentIndex = comments.firstIndex(where: { $0.id == comment.id }),
              let row = detailRows.firstIndex(where: {
                  if case .comment(let index, _) = $0 {
                      return index == commentIndex
                  }
                  return false
              }) else {
            return nil
        }
        return IndexPath(row: row, section: 0)
    }

    private func isLoadedCommentVisible(anchorID: String, indexPath: IndexPath) -> Bool {
        #if DEBUG
        if let testVisibleAnchorIDs {
            return testVisibleAnchorIDs.contains(normalizedAnchorText(anchorID))
        }
        #endif
        return tableNode.indexPathsForVisibleRows().contains(indexPath)
    }

    private func presentLoadedCommentPreview(comment: Comment, anchorID: String) {
        #if DEBUG
        testPresentedLoadedCommentID = comment.id
        testHighlightedAnchorID = nil
        testPresentedPreviewUsesCommentCellRendering = true
        testPresentedPreviewKeepsCloseButtonOutsideContent = true
        testPresentedPreviewUsesBottomSheet = true
        testPresentedPreviewShowsFullPostButton = wasOpenedFromInitialAnchor
        #endif
        let renderedContent = commentRenderedCache[comment.id] ?? Self.makeRenderedContent(
            html: comment.contentHTML,
            signatureHTML: comment.signatureHTML,
            baseURL: baseURL,
            maxImageWidth: availableCommentContentWidth,
            showsSignature: PostSignatureDisplaySettings.shared.showsSignatures
        )

        let previewController = LoadedCommentPreviewViewController(
            comment: comment,
            renderedContent: renderedContent,
            showsFullPostButton: wasOpenedFromInitialAnchor,
            onOpenFullPost: { [weak self] in
                self?.openFullPostFromFloorPreview()
            },
            onReveal: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.scrollToCurrentPageAnchor(anchorID)
                }
            }
        )
        let preferredSize = LoadedCommentPreviewViewController.preferredSize(
            comment: comment,
            renderedContent: renderedContent,
            containerSize: view.bounds.size
        )
        previewController.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
        previewController.modalPresentationStyle = .pageSheet
        previewController.preferredContentSize = preferredSize
        #if DEBUG
        testPresentedPreviewPreferredHeight = preferredSize.height
        #endif
        if let sheet = previewController.sheetPresentationController {
            let detentID = UISheetPresentationController.Detent.Identifier("floor-preview")
            if #available(iOS 16.0, *) {
                sheet.detents = [
                    .custom(identifier: detentID) { _ in
                        preferredSize.height
                    }
                ]
                sheet.selectedDetentIdentifier = detentID
            } else {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
            }
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.preferredCornerRadius = 18
        }
        present(previewController, animated: true)
    }

    private func openFullPostFromBeginning() {
        guard let header = currentHeaderContent else { return }
        let page = 1
        #if DEBUG
        testOpenedFullPostPage = page
        testOpenedFullPostAnchorWasNil = true
        #endif
        let post = PostSummary(
            id: header.postID,
            title: header.title,
            url: NodeSeekSite.postURL(id: header.postID, page: page),
            authorName: header.authorName,
            nodeName: nil,
            replyCount: 0,
            lastActivityText: header.metadataText,
            avatarURL: header.avatarURL
        )
        let viewController = PostDetailRouter.createModule(
            post: post,
            page: page,
            initialAnchorID: nil
        )
        if presentedViewController != nil {
            dismiss(animated: true) { [weak self] in
                self?.showDetailDestination(viewController)
            }
        } else {
            showDetailDestination(viewController)
        }
    }

    private func openFullPostFromFloorPreview() {
        guard wasOpenedFromInitialAnchor else { return }
        openFullPostFromBeginning()
    }

    var shouldShowInitialPageHint: Bool {
        initialPage > 1
    }

    func openFullPostFromEntryHint() {
        guard shouldShowInitialPageHint else { return }
        openFullPostFromBeginning()
    }

    func openUserInfo(profileURL: URL) {
        if let userID = NodeSeekUserIDResolver.uid(from: profileURL) {
            AppLog.info(.runtime, "打开原生用户资料，userID=\(userID), url=\(profileURL.absoluteString)")
            showDetailDestination(ProfileTabViewController(userID: userID))
            return
        }
        guard let username = NodeSeekMemberProfileResolver.memberUsername(from: profileURL) else {
            AppLog.warning(.runtime, "用户资料链接未解析到用户，不再打开网页资料页: \(profileURL.absoluteString)")
            showToast(message: "无法打开该用户资料")
            return
        }
        AppLog.info(.runtime, "解析站内用户名 user=\(username), url=\(profileURL.absoluteString)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let userID = try await NodeSeekMemberProfileResolver.resolveUserID(username: username)
                self.showDetailDestination(ProfileTabViewController(userID: userID))
            } catch {
                AppLog.warning(.runtime, "解析用户名失败: \(error.localizedDescription)")
                self.showToast(message: "无法打开该用户资料")
            }
        }
    }

    func consumeInitialAnchorIfNeeded() {
        guard let anchorID = pendingInitialAnchorID else { return }
        pendingInitialAnchorID = nil
        DispatchQueue.main.async { [weak self] in
            self?.scrollToCurrentPageAnchor(anchorID)
        }
    }

    func scrollToCurrentPageAnchor(_ anchorID: String) {
        guard displayMode == .content else { return }
        guard let indexPath = indexPathForCurrentPageAnchor(anchorID) else {
            AppLog.debug(.postDetail, "锚点未落在本页: anchor=\(anchorID), rows=\(detailRows.count)")
            return
        }
        AppLog.debug(.postDetail, "锚点滚动: anchor=\(anchorID), row=\(indexPath.row)")

        #if DEBUG
        testHighlightedAnchorID = normalizedAnchorText(anchorID)
        testPresentedLoadedCommentID = nil
        #endif
        tableNode.scrollToRow(at: indexPath, at: .middle, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            switch self.tableNode.nodeForRow(at: indexPath) {
            case let node as PostBodyCellNode:
                node.flashAnchorHighlight()
            case let node as CommentCellNode:
                node.flashAnchorHighlight()
            default:
                break
            }
        }
    }

    func indexPathForCurrentPageAnchor(_ anchorID: String) -> IndexPath? {
        let normalizedAnchorID = normalizedAnchorText(anchorID)
        if let commentIndex = comments.firstIndex(where: { comment in
            normalizedAnchorText(comment.anchorID) == normalizedAnchorID
                || normalizedAnchorText(comment.floorText) == normalizedAnchorID
        }), let row = detailRows.firstIndex(where: {
            if case .comment(let index, _) = $0 {
                return index == commentIndex
            }
            return false
        }) {
            return IndexPath(row: row, section: 0)
        }

        guard anchorID == "0", currentHeaderContent != nil,
              let row = detailRows.firstIndex(where: { if case .header = $0 { return true }; return false }) else {
            return nil
        }
        return IndexPath(row: row, section: 0)
    }

    #if DEBUG
    func testCurrentPageAnchorRow(for anchorID: String) -> Int? {
        indexPathForCurrentPageAnchor(anchorID)?.row
    }
    #endif

    func showDetailDestination(_ viewController: UIViewController) {
        if let navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else {
            present(UINavigationController(rootViewController: viewController), animated: true)
        }
    }

    func resolvedDetailURL() -> URL? {
        if let postID = currentHeaderContent?.postID, postID.isEmpty == false {
            return NodeSeekSite.postURL(id: postID, page: initialPage)
        }

        return sourcePostURL
    }

    func isNodeSeekHost(_ url: URL) -> Bool {
        NodeSeekSite.isNodeSeekHost(url)
    }

    #if DEBUG
    func testOpenFullPostFromFloorPreview() {
        openFullPostFromFloorPreview()
    }
    #endif

    private func normalizedAnchorID(from url: URL) -> String? {
        guard let fragment = url.fragment?.removingPercentEncoding else { return nil }
        return normalizedAnchorText(fragment)
    }

    private func normalizedAnchorText(_ text: String?) -> String {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false else {
            return ""
        }
        while text.hasPrefix("#") {
            text.removeFirst()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
