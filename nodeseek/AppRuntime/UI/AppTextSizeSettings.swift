//
//  AppTextSizeSettings.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import UIKit

final class AppTextSizeSettings {
    static let didChangeNotification = Notification.Name("AppTextSizeSettings.didChange")
    static let shared = AppTextSizeSettings()

    static let minimumPointOffset: CGFloat = -4
    static let maximumPointOffset: CGFloat = 8
    static let defaultPointOffset: CGFloat = 0

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "appTextSizePointOffset"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    var pointOffset: CGFloat {
        guard userDefaults.object(forKey: storageKey) != nil else {
            return Self.defaultPointOffset
        }
        return Self.normalizedPointOffset(CGFloat(userDefaults.double(forKey: storageKey)))
    }

    var displayText: String {
        Self.displayText(for: pointOffset)
    }

    func setPointOffset(_ rawValue: CGFloat) {
        let nextValue = Self.normalizedPointOffset(rawValue)
        guard nextValue != pointOffset else { return }
        userDefaults.set(Double(nextValue), forKey: storageKey)
        let postNotification = {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
        if Thread.isMainThread {
            postNotification()
        } else {
            DispatchQueue.main.async(execute: postNotification)
        }
    }

    func reset() {
        setPointOffset(Self.defaultPointOffset)
    }

    static func normalizedPointOffset(_ rawValue: CGFloat) -> CGFloat {
        min(max(rawValue.rounded(), minimumPointOffset), maximumPointOffset)
    }

    static func adjustedPointSize(basePointSize: CGFloat, pointOffset: CGFloat = shared.pointOffset) -> CGFloat {
        let adjustedSize = basePointSize + normalizedPointOffset(pointOffset)
        return max(8, adjustedSize * AppDisplayScaleSettings.shared.scale)
    }

    static func displayText(for pointOffset: CGFloat) -> String {
        let normalized = normalizedPointOffset(pointOffset)
        if normalized == 0 {
            return "标准"
        }
        return normalized > 0 ? "+\(Int(normalized))" : "\(Int(normalized))"
    }
}

enum AppTypography {
    /// 深色模式避免纯白正文刺眼，浅色模式仍沿用系统主文字颜色。
    static let primaryTextColor = UIColor { traits in
        guard traits.userInterfaceStyle == .dark else { return .label }
        return UIColor(red: 232.0 / 255.0, green: 232.0 / 255.0, blue: 237.0 / 255.0, alpha: 1)
    }

    static let secondaryTextColor = UIColor { traits in
        guard traits.userInterfaceStyle == .dark else { return .secondaryLabel }
        return UIColor(red: 174.0 / 255.0, green: 174.0 / 255.0, blue: 183.0 / 255.0, alpha: 1)
    }

    static func font(
        basePointSize: CGFloat,
        weight: UIFont.Weight = .regular,
        pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset
    ) -> UIFont {
        UIFont.systemFont(
            ofSize: AppTextSizeSettings.adjustedPointSize(
                basePointSize: basePointSize,
                pointOffset: pointOffset
            ),
            weight: weight
        )
    }

    static func monospacedFont(
        basePointSize: CGFloat,
        weight: UIFont.Weight = .regular,
        pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset
    ) -> UIFont {
        UIFont.monospacedSystemFont(
            ofSize: AppTextSizeSettings.adjustedPointSize(
                basePointSize: basePointSize,
                pointOffset: pointOffset
            ),
            weight: weight
        )
    }

    static func listTitleFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 17, weight: .medium, pointOffset: pointOffset)
    }

    static func listMetadataFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 13, weight: .regular, pointOffset: pointOffset)
    }

    static func commentAuthorFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 17, weight: .semibold, pointOffset: pointOffset)
    }

    static func commentBodyFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 17, weight: .regular, pointOffset: pointOffset)
    }

    static func commentMetadataFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 15, weight: .regular, pointOffset: pointOffset)
    }

    static func commentBadgeFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 11, weight: .regular, pointOffset: pointOffset)
    }

    static func commentActionFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 12, weight: .regular, pointOffset: pointOffset)
    }

    static func signatureFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 16, weight: .regular, pointOffset: pointOffset)
    }

    static func detailTitleFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 22, weight: .regular, pointOffset: pointOffset)
    }

    static func detailMetadataFont(pointOffset: CGFloat = AppTextSizeSettings.shared.pointOffset) -> UIFont {
        font(basePointSize: 15, weight: .regular, pointOffset: pointOffset)
    }
}
