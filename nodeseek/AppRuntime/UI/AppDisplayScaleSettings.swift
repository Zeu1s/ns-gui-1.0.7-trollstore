//
//  AppDisplayScaleSettings.swift
//  nodeseek
//

import Foundation
import UIKit

/// 用户选择的应用显示比例。文字和网页内容都通过这一设置保持一致。
final class AppDisplayScaleSettings {
    static let didChangeNotification = Notification.Name("AppDisplayScaleSettings.didChange")
    static let shared = AppDisplayScaleSettings()

    static let minimumScale: CGFloat = 0.7
    static let maximumScale: CGFloat = 1.2
    static let defaultScale: CGFloat = 1.0

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "appDisplayScale"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    var scale: CGFloat {
        guard userDefaults.object(forKey: storageKey) != nil else {
            return Self.defaultScale
        }
        return Self.normalizedScale(CGFloat(userDefaults.double(forKey: storageKey)))
    }

    var displayText: String {
        Self.displayText(for: scale)
    }

    func setScale(_ rawValue: CGFloat) {
        let nextValue = Self.normalizedScale(rawValue)
        guard nextValue != scale else { return }
        userDefaults.set(Double(nextValue), forKey: storageKey)

        let postNotifications = {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            // 复用既有文本重绘观察者，让列表和详情页立即采用新比例。
            NotificationCenter.default.post(name: AppTextSizeSettings.didChangeNotification, object: self)
        }
        if Thread.isMainThread {
            postNotifications()
        } else {
            DispatchQueue.main.async(execute: postNotifications)
        }
    }

    func reset() {
        setScale(Self.defaultScale)
    }

    static func normalizedScale(_ rawValue: CGFloat) -> CGFloat {
        let percentage = min(max((rawValue * 100).rounded(), minimumScale * 100), maximumScale * 100)
        return percentage / 100
    }

    static func scaled(_ value: CGFloat) -> CGFloat {
        value * shared.scale
    }

    static func displayText(for scale: CGFloat) -> String {
        "\(Int((normalizedScale(scale) * 100).rounded()))%"
    }
}
