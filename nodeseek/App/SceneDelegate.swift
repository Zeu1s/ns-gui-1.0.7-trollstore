//
//  SceneDelegate.swift
//  nodeseek
//
//  Created by mist on 2026/4/27.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        AppLog.info(.service, "场景连接")
        let window = UIWindow(windowScene: windowScene)
        let appRouter = AppRouter()
        window.rootViewController = NodeSeekSplashViewController { [weak window] in
            guard let window else { return }
            // 用 Splash 快照盖在新根视图上做淡出，衔接顺滑且不暴露中间帧
            let snapshot = window.snapshotView(afterScreenUpdates: false)
            UIView.performWithoutAnimation {
                window.rootViewController = appRouter.makeRootViewController()
                window.layoutIfNeeded()
            }
            guard let snapshot else { return }
            window.addSubview(snapshot)
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                options: [.curveEaseInOut]
            ) {
                snapshot.alpha = 0
                snapshot.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }
        window.makeKeyAndVisible()
        self.window = window
        NodeSeekTouchIntentFilter.shared.install(on: window)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        AppLog.info(.service, "场景断开")
        AppRuntimeMonitor.shared.sceneDidDisconnect()
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        AppLog.info(.service, "场景进入活跃状态")
        AppRuntimeMonitor.shared.sceneDidBecomeActive()
        NodeSeekNotificationPrefetcher.shared.resumeAfterForegroundActivationIfReady()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        AppLog.info(.service, "场景即将失去活跃状态")
        AppRuntimeMonitor.shared.sceneWillResignActive()
        NodeSeekNotificationPrefetcher.shared.stop()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        AppLog.info(.service, "场景进入前台")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppLog.info(.service, "场景进入后台")
        AppRuntimeMonitor.shared.sceneDidEnterBackground()
        VisitedPostStore.shared.flush()
    }
}
