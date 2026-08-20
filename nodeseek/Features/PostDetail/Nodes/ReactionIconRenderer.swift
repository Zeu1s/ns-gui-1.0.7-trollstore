//
//  ReactionIconRenderer.swift
//  nodeseek
//

import UIKit

enum ReactionIconRenderer {
    static func chickenLeg(pointSize: CGFloat) -> UIImage? {
        // 参照站点图标：圆润肉块、三枚小圆点和向右下延伸的骨柄。
        // 使用模板图保证详情操作、资料统计和长按菜单能跟随各自的状态色。
        let width = max(22, pointSize * 1.42)
        let height = max(19, pointSize * 1.16)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setFillColor(UIColor.black.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let strokeWidth = max(1.8, height * 0.098)
            let meat = UIBezierPath()
            meat.move(to: CGPoint(x: width * 0.11, y: height * 0.25))
            meat.addCurve(
                to: CGPoint(x: width * 0.61, y: height * 0.21),
                controlPoint1: CGPoint(x: width * 0.25, y: height * 0.03),
                controlPoint2: CGPoint(x: width * 0.51, y: height * 0.02)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.59, y: height * 0.65),
                controlPoint1: CGPoint(x: width * 0.74, y: height * 0.36),
                controlPoint2: CGPoint(x: width * 0.72, y: height * 0.53)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.17, y: height * 0.67),
                controlPoint1: CGPoint(x: width * 0.48, y: height * 0.79),
                controlPoint2: CGPoint(x: width * 0.28, y: height * 0.76)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.11, y: height * 0.25),
                controlPoint1: CGPoint(x: width * 0.04, y: height * 0.56),
                controlPoint2: CGPoint(x: width * 0.04, y: height * 0.37)
            )
            meat.close()
            meat.lineWidth = strokeWidth
            meat.stroke()

            let bone = UIBezierPath()
            bone.move(to: CGPoint(x: width * 0.59, y: height * 0.64))
            bone.addLine(to: CGPoint(x: width * 0.87, y: height * 0.89))
            bone.lineWidth = strokeWidth
            bone.stroke()

            let endRadius = max(1.7, height * 0.075)
            cg.fillEllipse(
                in: CGRect(
                    x: width * 0.87 - endRadius,
                    y: height * 0.89 - endRadius,
                    width: endRadius * 2,
                    height: endRadius * 2
                )
            )

            let dotRadius = max(1.25, height * 0.055)
            [
                CGPoint(x: width * 0.27, y: height * 0.40),
                CGPoint(x: width * 0.39, y: height * 0.34),
                CGPoint(x: width * 0.39, y: height * 0.52)
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
