//
//  ReactionIconRenderer.swift
//  nodeseek
//

import UIKit

enum ReactionIconRenderer {
    static func chickenLeg(pointSize: CGFloat) -> UIImage? {
        // 与 NodeSeek 的鸡腿线稿一致：圆润肉块、三枚小圆点和短骨柄。
        // 使用模板图保证详情操作、资料统计和长按菜单能跟随各自的状态色。
        let width = max(20, pointSize * 1.28)
        let height = max(19, pointSize * 1.14)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let strokeWidth = max(1.8, height * 0.105)
            let meat = UIBezierPath()
            meat.move(to: CGPoint(x: width * 0.10, y: height * 0.23))
            meat.addCurve(
                to: CGPoint(x: width * 0.56, y: height * 0.59),
                controlPoint1: CGPoint(x: width * 0.25, y: height * 0.01),
                controlPoint2: CGPoint(x: width * 0.59, y: height * 0.08)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.37, y: height * 0.88),
                controlPoint1: CGPoint(x: width * 0.70, y: height * 0.77),
                controlPoint2: CGPoint(x: width * 0.53, y: height * 0.98)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.10, y: height * 0.23),
                controlPoint1: CGPoint(x: width * 0.14, y: height * 0.88),
                controlPoint2: CGPoint(x: width * 0.01, y: height * 0.54)
            )
            meat.close()
            meat.lineWidth = strokeWidth
            meat.stroke()

            let bone = UIBezierPath()
            bone.move(to: CGPoint(x: width * 0.55, y: height * 0.61))
            bone.addLine(to: CGPoint(x: width * 0.83, y: height * 0.88))
            bone.lineWidth = strokeWidth
            bone.stroke()

            let endRadius = max(1.7, height * 0.075)
            cg.fillEllipse(
                in: CGRect(
                    x: width * 0.83 - endRadius,
                    y: height * 0.88 - endRadius,
                    width: endRadius * 2,
                    height: endRadius * 2
                )
            )

            let dotRadius = max(1.25, height * 0.055)
            [
                CGPoint(x: width * 0.27, y: height * 0.42),
                CGPoint(x: width * 0.37, y: height * 0.35),
                CGPoint(x: width * 0.37, y: height * 0.54)
            ].forEach { center in
                cg.fillEllipse(
                    in: CGRect(
                        x: center.x - dotRadius,
                        y: center.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                )
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
