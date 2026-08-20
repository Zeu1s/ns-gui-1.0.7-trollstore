//
//  ReactionIconRenderer.swift
//  nodeseek
//

import UIKit

enum ReactionIconRenderer {
    static func chickenLeg(pointSize: CGFloat) -> UIImage? {
        // Match the NodeSeek reaction glyph instead of relying on an emoji or
        // a font-dependent symbol. The result remains tintable by the action state.
        let width = max(18, pointSize * 1.22)
        let height = max(18, pointSize * 1.08)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let meat = UIBezierPath()
            meat.move(to: CGPoint(x: width * 0.13, y: height * 0.19))
            meat.addCurve(
                to: CGPoint(x: width * 0.56, y: height * 0.60),
                controlPoint1: CGPoint(x: width * 0.37, y: height * 0.02),
                controlPoint2: CGPoint(x: width * 0.67, y: height * 0.31)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.30, y: height * 0.90),
                controlPoint1: CGPoint(x: width * 0.50, y: height * 0.82),
                controlPoint2: CGPoint(x: width * 0.39, y: height * 0.94)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.13, y: height * 0.19),
                controlPoint1: CGPoint(x: width * 0.05, y: height * 0.80),
                controlPoint2: CGPoint(x: width * 0.01, y: height * 0.40)
            )
            meat.close()
            meat.lineWidth = max(1.6, height * 0.09)
            meat.stroke()

            let bone = UIBezierPath()
            bone.move(to: CGPoint(x: width * 0.51, y: height * 0.61))
            bone.addLine(to: CGPoint(x: width * 0.76, y: height * 0.84))
            bone.lineWidth = max(1.6, height * 0.09)
            bone.stroke()

            let upperBoneEnd = UIBezierPath(ovalIn: CGRect(
                x: width * 0.68,
                y: height * 0.73,
                width: width * 0.20,
                height: height * 0.18
            ))
            upperBoneEnd.lineWidth = max(1.5, height * 0.08)
            upperBoneEnd.stroke()
            let lowerBoneEnd = UIBezierPath(ovalIn: CGRect(
                x: width * 0.79,
                y: height * 0.83,
                width: width * 0.18,
                height: height * 0.16
            ))
            lowerBoneEnd.lineWidth = max(1.5, height * 0.08)
            lowerBoneEnd.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
