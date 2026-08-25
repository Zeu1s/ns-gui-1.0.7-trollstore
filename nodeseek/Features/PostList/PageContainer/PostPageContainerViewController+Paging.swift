//
//  PostPageContainerViewController+Paging.swift
//  nodeseek
//

import UIKit

extension PostPageContainerViewController: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let host = viewController as? PostTextureListHostViewController,
              let index = categories.firstIndex(of: host.category),
              index > 0 else {
            return nil
        }
        return hostViewControllers[categories[index - 1]]
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let host = viewController as? PostTextureListHostViewController,
              let index = categories.firstIndex(of: host.category),
              index < categories.count - 1 else {
            return nil
        }
        return hostViewControllers[categories[index + 1]]
    }
}

extension PostPageContainerViewController: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        beginPagingTransition()
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        defer { finishPagingTransition() }
        // 即使手势取消，也要以分页器最终保留的页面同步状态；否则返回首页时
        // currentCategory 可能仍指向被取消的目标页，进而让内容区重设为空白页。
        guard let current = pageViewController.viewControllers?.first as? PostTextureListHostViewController else {
            return
        }
        updateCurrentCategoryAfterPaging(current.category)
        guard finished, completed else { return }
        eventDelegate?.postPageContainerViewController(self, didScrollTo: current.category)
    }
}
