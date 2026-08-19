//
//  ReactionIconRenderer.swift
//  nodeseek
//

import UIKit

enum ReactionIconRenderer {
    static func chickenLeg(pointSize: CGFloat) -> UIImage? {
        // Draw a small monochrome drumstick so its silhouette is stable on every
        // iOS font set and remains tintable in both comment and post cells.
        let width = max(16, pointSize * 1.15)
        let height = max(16, pointSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            cg.saveGState()
            cg.translateBy(x: width * 0.48, y: height * 0.46)
            cg.rotate(by: -.48)
            let body = UIBezierPath(ovalIn: CGRect(
                x: -width * 0.29,
                y: -height * 0.36,
                width: width * 0.58,
                height: height * 0.68
            ))
            body.fill()
            cg.restoreGState()

            cg.setLineWidth(max(2, height * 0.16))
            cg.move(to: CGPoint(x: width * 0.58, y: height * 0.62))
            cg.addLine(to: CGPoint(x: width * 0.86, y: height * 0.88))
            cg.strokePath()
            cg.fillEllipse(in: CGRect(
                x: width * 0.78,
                y: height * 0.79,
                width: width * 0.22,
                height: height * 0.18
            ))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
