//
//  ProfileTabViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class ProfileTabViewController: UIViewController {
    private var didLoadOnce = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "我的"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        guard didLoadOnce == false else { return }
        didLoadOnce = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let account = await CurrentAccountStore.shared.snapshot()
            let profileURL = account?.account.profileURL ?? NodeSeekSite.baseURL
            let profileViewController = UserInfoWebViewController(profileURL: profileURL, title: "我的")
            self.navigationController?.setViewControllers([profileViewController], animated: false)
        }
    }
}