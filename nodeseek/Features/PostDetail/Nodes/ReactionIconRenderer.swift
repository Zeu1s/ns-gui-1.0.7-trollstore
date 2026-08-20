//
//  ReactionIconRenderer.swift
//  nodeseek
//

import UIKit

enum ReactionIconRenderer {
    static func chickenLeg(pointSize: CGFloat) -> UIImage? {
        // 与点赞/踩 SF Symbol 风格统一：实心、圆润、饱满的鼓槌造型，
        // 肉块+骨柄+末端关节，模板图跟随状态色（未点灰、已点橙）。
        let width = max(20, pointSize * 1.30)
        let height = max(18, pointSize * 1.02)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setFillColor(UIColor.black.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            // 肉块：实心填充，圆角轮廓与点赞/踩的粗壮笔画呼应
            let meat = UIBezierPath()
            meat.move(to: CGPoint(x: width * 0.10, y: height * 0.36))
            meat.addCurve(
                to: CGPoint(x: width * 0.62, y: height * 0.22),
                controlPoint1: CGPoint(x: width * 0.24, y: height * 0.05),
                controlPoint2: CGPoint(x: width * 0.52, y: height * 0.05)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.71, y: height * 0.60),
                controlPoint1: CGPoint(x: width * 0.78, y: height * 0.34),
                controlPoint2: CGPoint(x: width * 0.78, y: height * 0.50)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.22, y: height * 0.78),
                controlPoint1: CGPoint(x: width * 0.55, y: height * 0.88),
                controlPoint2: CGPoint(x: width * 0.34, y: height * 0.86)
            )
            meat.addCurve(
                to: CGPoint(x: width * 0.10, y: height * 0.36),
                controlPoint1: CGPoint(x: width * 0.06, y: height * 0.66),
                controlPoint2: CGPoint(x: width * 0.05, y: height * 0.49)
            )
            meat.close()
            meat.lineWidth = max(1.6, height * 0.075)
            meat.lineJoinStyle = .round
            meat.lineCapStyle = .round
            meat.fill()
            meat.stroke()

            // 骨柄：圆头粗线向右下延伸
            let boneWidth = max(2.1, height * 0.115)
            let boneStart = CGPoint(x: width * 0.58, y: height * 0.58)
            let boneEnd = CGPoint(x: width * 0.86, y: height * 0.88)
            let bone = UIBezierPath()
            bone.move(to: boneStart)
            bone.addLine(to: boneEnd)
            bone.lineWidth = boneWidth
            bone.lineCapStyle = .round
            bone.stroke()

            // 末端关节
            let endRadius = boneWidth * 0.85
            cg.fillEllipse(
                in: CGRect(
                    x: boneEnd.x - endRadius,
                    y: boneEnd.y - endRadius,
                    width: endRadius * 2,
                    height: endRadius * 2
                )
            )
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}