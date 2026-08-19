//
//  ReactionIconRenderer.swift
//  nodeseek
//

import UIKit

enum ReactionIconRenderer {
    static func chickenLeg(pointSize: CGFloat) -> UIImage? {
        let font = UIFont.systemFont(ofSize: pointSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let string = NSAttributedString(string: "🍗", attributes: attributes)
        let size = string.size()
        guard size.width > 0, size.height > 0 else { return nil }

        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        string.draw(at: .zero)
        let base = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let base else { return nil }

        let rotated = rotate180(base)

        let outlinePadding: CGFloat = 4
        let canvasSize = CGSize(width: rotated.size.width + outlinePadding * 2, height: rotated.size.height + outlinePadding * 2)
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 0)
        UIColor.white.set()
        let offsets: [CGPoint] = [
            CGPoint(x: -2, y: -2), CGPoint(x: 0, y: -2), CGPoint(x: 2, y: -2),
            CGPoint(x: -2, y: 0), CGPoint(x: 2, y: 0),
            CGPoint(x: -2, y: 2), CGPoint(x: 0, y: 2), CGPoint(x: 2, y: 2)
        ]
        for offset in offsets {
            rotated.draw(at: CGPoint(x: outlinePadding + offset.x, y: outlinePadding + offset.y))
        }
        rotated.draw(at: CGPoint(x: outlinePadding, y: outlinePadding))
        let outlined = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return outlined
    }

    private static func rotate180(_ image: UIImage) -> UIImage {
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: .pi)
        context.translateBy(x: -size.width / 2, y: -size.height / 2)
        image.draw(at: .zero)
        let rotated = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotated ?? image
    }
}