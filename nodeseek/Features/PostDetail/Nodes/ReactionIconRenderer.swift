//
//  ReactionIconRenderer.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

enum ReactionIconRenderer {
        private static let chickenLegFilledSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" fill="none"><g><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" fill="#000000" d="M33.375 33.874c4.242-4.242 1.414-18.384-4.95-24.748-2.828-2.829-10.96-8.84-19.799 0-8.839 8.838-2.828 16.97 0 19.799 6.364 6.364 20.506 9.192 24.749 4.95Z"></path><path stroke-width="4" stroke="#000000" d="m41 41-7-7"></path><circle fill="#000000" transform="rotate(135 42.193 40.071)" r="2.5" cy="40.071" cx="42.193"></circle><circle fill="#000000" transform="rotate(135 40.072 42.192)" r="2.5" cy="42.192" cx="40.072"></circle><circle fill="#000000" r="2" cy="18" cx="17"></circle><circle fill="#000000" r="2" cy="21" cx="12"></circle><circle fill="#000000" r="2" cy="24" cx="17"></circle></g></svg>
    """
        private static let chickenLegOutlinedSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" fill="none"><g><path stroke-linejoin="round" stroke-linecap="round" stroke-width="4" stroke="#000000" d="M33.375 33.874c4.242-4.242 1.414-18.384-4.95-24.748-2.828-2.829-10.96-8.84-19.799 0-8.839 8.838-2.828 16.97 0 19.799 6.364 6.364 20.506 9.192 24.749 4.95Z"></path><path stroke-width="4" stroke="#000000" d="m41 41-7-7"></path><circle fill="#000000" transform="rotate(135 42.193 40.071)" r="2.5" cy="40.071" cx="42.193"></circle><circle fill="#000000" transform="rotate(135 40.072 42.192)" r="2.5" cy="42.192" cx="40.072"></circle><circle fill="#000000" r="2" cy="18" cx="17"></circle><circle fill="#000000" r="2" cy="21" cx="12"></circle><circle fill="#000000" r="2" cy="24" cx="17"></circle></g></svg>
    """
    private static let chickenLegImageCache = NSCache<NSString, UIImage>()

    /// 图形为站点官方 IconPark chicken-leg（nodeseek.com sprite 同源）。颜色由调用方 tint，空心/实心由 isFilled 控制。
    static func chickenLeg(pointSize: CGFloat, isFilled: Bool = false) -> UIImage? {
        let side = max(18, pointSize * 1.08)
        let cacheKey = "\(Int((side * UIScreen.main.scale).rounded()))-\(isFilled)" as NSString
        if let cachedImage = chickenLegImageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        let svg = isFilled ? chickenLegFilledSVG : chickenLegOutlinedSVG
        guard let image = SVGImageRenderer.image(
            from: Data(svg.utf8),
            size: CGSize(width: side, height: side)
        )?.withRenderingMode(.alwaysTemplate) else {
            return nil
        }
        chickenLegImageCache.setObject(image, forKey: cacheKey)
        return image
    }}
