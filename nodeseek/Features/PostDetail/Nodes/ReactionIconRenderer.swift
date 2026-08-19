//
//  ReactionIconRenderer.swift
//  nodeseek
//

import UIKit

enum ReactionIconRenderer {
    static func chickenLeg(pointSize: CGFloat) -> UIImage? {
        // 使用线性轮廓，避免 Emoji 在不同 iOS 字体下变成彩色或尺寸跳变。
        let configuration = UIImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .regular,
            scale: .medium
        )
        return UIImage(systemName: "ellipsis.bubble", withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate)
    }
}
