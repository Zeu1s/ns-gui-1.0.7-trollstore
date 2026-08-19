//
//  PostListViewController+PageContainerDelegate.swift
//  nodeseek
//

import UIKit

extension PostListViewController: PostPageContainerViewControllerDelegate {
    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didSelectPost post: PostSummary,
        category: PostListCategoryItem
    ) {
        syncSelectedCategoryFromPageContainerIfNeeded(category)
        presenter.didSelectPost(post)
    }

    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didChangeSortMode sortMode: PostListSortMode,
        category: PostListCategoryItem
    ) {
        syncSelectedCategoryFromPageContainerIfNeeded(category)
        renderSortMode(sortMode)
    }

    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didScrollTo category: PostListCategoryItem
    ) {
        let categoryChanged = category != selectedCategory
        syncSelectedCategoryFromPageContainerIfNeeded(category)
        renderSortMode(containerView.sortMode(for: category))
        if categoryChanged {
            // 切换板块后从该板块顶部开始浏览；保留旧内容直到新请求完成，避免闪屏。
            containerView.scrollToTop(for: category, animated: false)
            containerView.refreshFirstPageKeepingContent(for: category)
        }
    }

    func postPageContainerViewController(
        _ containerView: PostPageContainerViewController,
        didLoadFirstPageFor category: PostListCategoryItem
    ) {
        containerView.scrollToTop(for: category, animated: false)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await autoCheckInRunner(self)
        }
    }

    func postPageContainerViewControllerDidRequestLeadingSideMenu(_ containerView: PostPageContainerViewController) {
        menuButtonFeedbackGenerator.impactOccurred()
        sideMenuViewController.show(animated: true)
    }

    private func syncSelectedCategoryFromPageContainerIfNeeded(_ category: PostListCategoryItem) {
        guard category != selectedCategory else { return }
        selectedCategory = category
        applySelectedCategory(category, syncPage: false, pageAnimated: false)
        presenter.didSelectCategory(category)
    }
}
