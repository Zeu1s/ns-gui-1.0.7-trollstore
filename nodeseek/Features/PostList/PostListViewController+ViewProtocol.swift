//
//  PostListViewController+ViewProtocol.swift
//  nodeseek
//

import UIKit

extension PostListViewController: PostListViewProtocol {
    func showError(message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    #if DEBUG
    func openDetailTestURLFromPasteboard() {
        guard NodeSeekDebugConfig.enablePostDetailTestEntry else { return }
        presenter.didSubmitDetailTestURL(detailTestURLProvider())
    }
    #endif

    func renderNotificationUnreadBadge(isVisible: Bool) {
        applyNotificationUnreadBadge(isVisible: isVisible)
    }

    func renderCategories(_ categories: [PostListCategoryItem], selected: PostListCategoryItem) {
        let displayCategories = [PostListCategoryItem.specialFollow] + categories.filter { $0.isSpecialFollow == false }
        let categoriesChanged = displayCategories != self.categories
        if categoriesChanged {
            self.categories = displayCategories
            rebuildCategoryButtons()
            pageContainerViewController.configure(categories: displayCategories)
        }
        selectedCategory = selected
        applySelectedCategory(selected, syncPage: categoriesChanged, pageAnimated: false)
    }

    func renderSortMode(_ sortMode: PostListSortMode) {
        currentSortMode = sortMode
        sortToggleButton.apply(sortMode: sortMode, expanded: isSortToggleExpanded)
        if isSortToggleExpanded {
            sortToggleWidthConstraint?.constant = PostListSortToggleButton.expandedWidth(for: sortMode.accessibilityTitle)
        }
    }

    func reloadSelectedCategory() {
        pageContainerViewController.reloadFirstPage(for: selectedCategory)
    }
}
