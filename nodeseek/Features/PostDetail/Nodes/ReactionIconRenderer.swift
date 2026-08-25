//
//  ReactionIconRenderer.swift
//  nodeseek
//

import UIKit

enum ReactionIconRenderer {
    private static let chickenLegFilledSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
      <g transform="translate(256, 256) scale(1.8)" stroke-width="14" stroke-linecap="round" stroke-linejoin="round">
        <path d="M -90 20 A 80 80 0 1 1 20 -90 C 60 -50, 60 5, 40 30 L 90 80 A 20 20 0 1 1 115 115 A 20 20 0 1 1 80 90 L 30 40 C 5 60, -50 60, -90 20 Z" fill="#000000" stroke="#000000"/>
      </g>
    </svg>
    """
    private static let chickenLegOutlinedSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
      <g transform="translate(256, 256) scale(1.8)" stroke-width="14" stroke-linecap="round" stroke-linejoin="round">
        <path d="M -90 20 A 80 80 0 1 1 20 -90 C 60 -50, 60 5, 40 30 L 90 80 A 20 20 0 1 1 115 115 A 20 20 0 1 1 80 90 L 30 40 C 5 60, -50 60, -90 20 Z" fill="none" stroke="#000000"/>
      </g>
    </svg>
    """
    private static let chickenLegImageCache = NSCache<NSString, UIImage>()

    /// 图形源自用户提供的 SVG。颜色一律由调用方 tint，空心/实心由 isFilled 控制。
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
