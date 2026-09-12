//
//  NodeSeekIconRenderer.swift
//  nodeseek
//

import SVGKit
import UIKit

/// 站点官方 IconPark 图标的统一渲染入口。
/// 图形与 nodeseek.com 同源（见 NodeSeekIconArtwork），颜色一律交给 tintColor。
enum NodeSeekIconRenderer {
    private static let imageCache = NSCache<NSString, UIImage>()

    static func icon(_ name: String, pointSize: CGFloat) -> UIImage? {
        let side = max(18, pointSize * 1.08)
        let cacheKey = "icon-\(name)-\(Int((side * UIScreen.main.scale).rounded()))" as NSString
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        guard let artwork = artwork(for: name) else { return nil }
        let image = SVGImageRenderer.image(
            from: Data(artwork.utf8),
            size: CGSize(width: side, height: side)
        )?.withRenderingMode(.alwaysTemplate)
        if let image {
            imageCache.setObject(image, forKey: cacheKey)
        }
        return image
    }
}

// artwork(for:) 在扩展中按 name 分发，避免单个文件过长。

extension NodeSeekIconRenderer {
    static func artwork(for name: String) -> String? {
        switch name {
        case NodeSeekIconName.chickenLeg: return NodeSeekIconArtwork.chickenLeg
        case NodeSeekIconName.like: return NodeSeekIconArtwork.like
        case NodeSeekIconName.oppose: return NodeSeekIconArtwork.oppose
        case NodeSeekIconName.favorite: return NodeSeekIconArtwork.favorite
        case NodeSeekIconName.joinDays: return NodeSeekIconArtwork.joinDays
        case NodeSeekIconName.level: return NodeSeekIconArtwork.level
        case NodeSeekIconName.levelOutline: return NodeSeekIconArtwork.levelOutline
        case NodeSeekIconName.topics: return NodeSeekIconArtwork.topics
        case NodeSeekIconName.edit: return NodeSeekIconArtwork.edit
        case NodeSeekIconName.comments: return NodeSeekIconArtwork.comments
        case NodeSeekIconName.commentsAlt: return NodeSeekIconArtwork.commentsAlt
        case NodeSeekIconName.topicsAlt: return NodeSeekIconArtwork.topicsAlt
        case NodeSeekIconName.likeFilled: return NodeSeekIconArtwork.likeFilled
        case NodeSeekIconName.opposeFilled: return NodeSeekIconArtwork.opposeFilled
        case NodeSeekIconName.collection: return NodeSeekIconArtwork.collection
        case NodeSeekIconName.stardust: return NodeSeekIconArtwork.stardust
        case NodeSeekIconName.follow: return NodeSeekIconArtwork.follow
        case NodeSeekIconName.messages: return NodeSeekIconArtwork.messages
        default: return nil
        }
    }
}
