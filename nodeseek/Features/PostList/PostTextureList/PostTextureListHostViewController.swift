//
//  PostTextureListHostViewController.swift
//  nodeseek
//

import UIKit

final class PostTextureListHostViewController: UIViewController {
    let category: PostListCategoryItem

    private let presenter: PostTextureListHostPresenterProtocol
    private let listView = PostTextureListView()

    init(
        category: PostListCategoryItem,
        presenter: PostTextureListHostPresenterProtocol
    ) {
        self.category = category
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        listView.delegate = self
        listView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(listView)
        listView.isSpecialFollow = category.isSpecialFollow
        NSLayoutConstraint.activate([
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.topAnchor.constraint(equalTo: view.topAnchor),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        presenter.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 页面切换被手势打断后，UIPageViewController 可能不再触发首次加载回调。
        // 在真正可见时再兜底一次，避免板块停留在空白页。
        presenter.ensureFirstPageLoaded()
    }

    func ensureFirstPageLoaded() {
        loadViewIfNeeded()
        presenter.ensureFirstPageLoaded()
    }
    var currentSortMode: PostListSortMode {
        presenter.currentSortMode
    }

    var isReadyForDisplay: Bool {
        presenter.isReadyForDisplay
    }

    func toggleSortMode() -> PostListSortMode {
        presenter.toggleSortMode()
    }

    func reloadFirstPage() {
        presenter.reloadFirstPage()
    }

    func refreshFirstPageKeepingContent() {
        presenter.refreshFirstPageKeepingContent()
    }

    func scrollToTop(animated: Bool) {
        loadViewIfNeeded()
        listView.scrollToTop(animated: animated)
    }

    func refreshVisibleAppearanceForCurrentTraits() {
        guard isViewLoaded else { return }
        listView.refreshVisibleAppearanceForCurrentTraits()
    }

    func replayStreamAppearanceIfNeeded() {
        guard isViewLoaded else { return }
        presenter.replayStreamAppearance()
    }
}

extension PostTextureListHostViewController: PostTextureListViewDelegate {
    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int) {
        presenter.didSelectPost(at: index)
    }

    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView) {
        presenter.didRequestRefresh()
    }

    func postTextureListViewDidRequestFirstPageRetry(_ textureListView: PostTextureListView) {
        presenter.didRequestFirstPageRetry()
    }

    func postTextureListView(_ textureListView: PostTextureListView, didApproachBottomAt index: Int, totalCount: Int) {
        presenter.didApproachBottom(at: index, totalCount: totalCount)
    }
}

extension PostTextureListHostViewController: PostTextureListHostViewProtocol {
    func setItems(_ items: [PostListItem]) {
        listView.setItems(items)
    }

    func showLoadingSkeleton() {
        listView.showLoadingSkeleton()
    }

    func hideLoadingSkeleton() {
        listView.hideLoadingSkeleton()
    }

    func showFirstPageError(message: String) {
        listView.showFirstPageError(message: message)
    }

    func hideFirstPageError() {
        listView.hideFirstPageError()
    }

    func hideRefreshing() {
        listView.hideRefreshing()
    }

    func showLoadingMore() {
        listView.showLoadingMore()
    }

    func hideLoadingMore() {
        listView.hideLoadingMore()
    }

    func updateVisitedState(at index: Int, isVisited: Bool) {
        listView.updateVisitedState(at: index, isVisited: isVisited)
    }

    func replayStreamAppearance() {
        listView.replayStreamAppearance()
    }
}
