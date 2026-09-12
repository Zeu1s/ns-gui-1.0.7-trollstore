//
//  AppDelegate.swift
//  nodeseek
//
//  Created by mist on 2026/4/27.
//

import UIKit
import WebKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    private var keyWindowObserver: NSObjectProtocol?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        AppLog.installUncaughtExceptionHandler()
        AppCrashReporter.install()
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let buildNumber = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        let systemVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        AppLog.important(.error, .service, "应用启动: v\(appVersion) (\(buildNumber)) · iOS \(systemVersion) · \(deviceModel)")
        AppRuntimeMonitor.shared.applicationDidLaunch()
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? UIWindow else { return }
            NodeSeekTouchIntentFilter.shared.install(on: window)
        }
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppRuntimeMonitor.shared.applicationWillTerminate()
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

/// 只有明确的点按才保留给业务控件；长按不再在列表、卡片和图片上落成一次点击。
/// 文本输入与网页内容仍交给系统自身处理，避免影响编辑和网页缩放。
final class NodeSeekTouchIntentFilter: NSObject, UIGestureRecognizerDelegate {
    static let shared = NodeSeekTouchIntentFilter()

    private weak var installedWindow: UIWindow?
    private weak var longPressRecognizer: UILongPressGestureRecognizer?

    private override init() {}

    func install(on window: UIWindow) {
        guard installedWindow !== window else { return }
        if let recognizer = longPressRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }

        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized(_:)))
        recognizer.minimumPressDuration = 0.45
        recognizer.allowableMovement = 12
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
        installedWindow = window
        longPressRecognizer = recognizer
    }

    @objc private func longPressRecognized(_ recognizer: UILongPressGestureRecognizer) {
        // 手势被识别时 UIKit 会向当前触摸目标发送取消事件；不执行任何业务动作。
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === longPressRecognizer else { return true }
        return isTextInputOrWebContent(touch.view) == false
    }

    private func isTextInputOrWebContent(_ view: UIView?) -> Bool {
        var currentView = view
        while let view = currentView {
            if view is UITextView || view is UITextField || view is WKWebView {
                return true
            }
            currentView = view.superview
        }
        return false
    }
}
