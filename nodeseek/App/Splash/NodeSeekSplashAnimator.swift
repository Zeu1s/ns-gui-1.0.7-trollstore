//
//  NodeSeekSplashAnimator.swift
//  nodeseek
//

import UIKit

nonisolated enum NodeSeekSplashTimeline {
    static let animationDuration: CFTimeInterval = 1.65
    static let reduceMotionDuration: CFTimeInterval = 0.18

    static let nDuration: CFTimeInterval = 0.72
    static let nLeftDuration: CFTimeInterval = nDuration * 0.31
    static let nDiagonalDuration: CFTimeInterval = nDuration * 0.39
    static let nFinalDuration: CFTimeInterval = nDuration - nLeftDuration - nDiagonalDuration

    static let sDuration: CFTimeInterval = 0.58
    static let dotBegin: CFTimeInterval = 1.30
    static let dotDuration: CFTimeInterval = 0.30
}

@MainActor
final class NodeSeekSplashAnimator: NSObject {
    private weak var containerView: UIView?
    private let reduceMotion: Bool
    private let animationDuration: CFTimeInterval

    private let backgroundLayer = CALayer()
    private let nLeftStrokeLayer = CAShapeLayer()
    private let nDiagonalStrokeLayer = CAShapeLayer()
    private let nFinalStrokeLayer = CAShapeLayer()
    private let sLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private let leftWaveLayer = CAShapeLayer()
    private let nodeCoreLayer = CAShapeLayer()
    private let nodeEyesLayer = CAShapeLayer()
    private let brandImageLayer = CALayer()
    private let rightWaveLayer = CAShapeLayer()
    private let wordmarkLayer = CATextLayer()
    private let wordmarkLeftLayer = CATextLayer()
    private let wordmarkRightLayer = CATextLayer()
    private var completion: (() -> Void)?

    init(
        reduceMotion: Bool? = nil,
        animationDuration: CFTimeInterval = NodeSeekSplashTimeline.animationDuration
    ) {
        self.reduceMotion = reduceMotion ?? UIAccessibility.isReduceMotionEnabled
        self.animationDuration = animationDuration
        super.init()
    }

    func install(in view: UIView) {
        containerView = view
        configureLayerNames()
        layoutBrandLayers(in: view.bounds)
        view.layer.addSublayer(leftWaveLayer)
        view.layer.addSublayer(rightWaveLayer)
        view.layer.addSublayer(nodeCoreLayer)
        view.layer.addSublayer(nodeEyesLayer)
        view.layer.addSublayer(brandImageLayer)
        view.layer.addSublayer(wordmarkLeftLayer)
        view.layer.addSublayer(wordmarkRightLayer)
        view.layer.addSublayer(wordmarkLayer)
    }

    func play(completion: @escaping () -> Void) {
        self.completion = completion

        guard !reduceMotion else {
            pinModelLayersToFinalFrame()
            DispatchQueue.main.asyncAfter(deadline: .now() + NodeSeekSplashTimeline.reduceMotionDuration) { [weak self] in
                self?.complete()
            }
            return
        }

        startAnimationTimeline()
    }

    func relayout() {
        guard let containerView else { return }
        layoutBrandLayers(in: containerView.bounds)
    }

    func updateColors(for traitCollection: UITraitCollection) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyBrandColors(for: traitCollection)
        CATransaction.commit()
    }
}

private extension NodeSeekSplashAnimator {
    func configureLayerNames() {
        backgroundLayer.name = "splash.background"
        nLeftStrokeLayer.name = "splash.n.leftStroke"
        nDiagonalStrokeLayer.name = "splash.n.diagonalStroke"
        nFinalStrokeLayer.name = "splash.n.finalStroke"
        sLayer.name = "splash.s"
        dotLayer.name = "splash.dot"
        leftWaveLayer.name = "splash.nodeseek.leftWaves"
        nodeCoreLayer.name = "splash.nodeseek.core"
        nodeEyesLayer.name = "splash.nodeseek.eyes"
        brandImageLayer.name = "splash.nodeseek.image"
        rightWaveLayer.name = "splash.nodeseek.rightWaves"
        wordmarkLayer.name = "splash.nodeseek.wordmark"
        wordmarkLeftLayer.name = "splash.nodeseek.wordmark.left"
        wordmarkRightLayer.name = "splash.nodeseek.wordmark.right"
    }

    func layoutBrandLayers(in bounds: CGRect) {
        let glyphWidth = min(bounds.width * 0.52, 258)
        let glyphHeight = glyphWidth * 0.62
        let glyphFrame = CGRect(
            x: bounds.midX - glyphWidth / 2,
            y: bounds.midY - glyphHeight * 0.60,
            width: glyphWidth,
            height: glyphHeight
        )
        let coreDiameter = glyphHeight * 0.78
        let coreFrame = CGRect(
            x: glyphFrame.midX - coreDiameter / 2,
            y: glyphFrame.midY - coreDiameter / 2,
            width: coreDiameter,
            height: coreDiameter
        )

        nodeCoreLayer.frame = bounds
        nodeCoreLayer.path = UIBezierPath(ovalIn: coreFrame).cgPath
        nodeCoreLayer.contentsScale = UIScreen.main.scale

        let brandSide = glyphWidth * 0.84
        brandImageLayer.frame = CGRect(
            x: glyphFrame.midX - brandSide / 2,
            y: glyphFrame.midY - brandSide / 2,
            width: brandSide,
            height: brandSide
        )
        brandImageLayer.contents = UIImage(named: "SplashLogo")?.cgImage
        brandImageLayer.contentsGravity = .resizeAspect
        brandImageLayer.contentsScale = UIScreen.main.scale
        brandImageLayer.cornerRadius = brandSide * 0.2237
        brandImageLayer.masksToBounds = true

        let eyeWidth = coreDiameter * 0.16
        let eyeHeight = coreDiameter * 0.25
        let eyeGap = coreDiameter * 0.18
        let eyesPath = UIBezierPath()
        eyesPath.append(UIBezierPath(roundedRect: CGRect(
            x: coreFrame.midX - eyeGap / 2 - eyeWidth,
            y: coreFrame.midY - eyeHeight / 2,
            width: eyeWidth,
            height: eyeHeight
        ), cornerRadius: eyeWidth / 2))
        eyesPath.append(UIBezierPath(roundedRect: CGRect(
            x: coreFrame.midX + eyeGap / 2,
            y: coreFrame.midY - eyeHeight / 2,
            width: eyeWidth,
            height: eyeHeight
        ), cornerRadius: eyeWidth / 2))
        nodeEyesLayer.frame = bounds
        nodeEyesLayer.path = eyesPath.cgPath
        nodeEyesLayer.fillRule = .evenOdd
        nodeEyesLayer.contentsScale = UIScreen.main.scale

        let waveLineWidth = max(6, glyphWidth * 0.045)
        leftWaveLayer.frame = bounds
        leftWaveLayer.path = wavePath(
            center: CGPoint(x: coreFrame.minX - glyphWidth * 0.10, y: coreFrame.midY),
            radius: glyphHeight * 0.39,
            opensToLeft: true
        ).cgPath
        leftWaveLayer.fillColor = UIColor.clear.cgColor
        leftWaveLayer.lineWidth = waveLineWidth
        leftWaveLayer.lineCap = .round
        leftWaveLayer.contentsScale = UIScreen.main.scale

        rightWaveLayer.frame = bounds
        rightWaveLayer.path = wavePath(
            center: CGPoint(x: coreFrame.maxX + glyphWidth * 0.10, y: coreFrame.midY),
            radius: glyphHeight * 0.39,
            opensToLeft: false
        ).cgPath
        rightWaveLayer.fillColor = UIColor.clear.cgColor
        rightWaveLayer.lineWidth = waveLineWidth
        rightWaveLayer.lineCap = .round
        rightWaveLayer.contentsScale = UIScreen.main.scale

        let wordmarkWidth = min(bounds.width * 0.62, 238)
        let wordmarkFrame = CGRect(
            x: bounds.midX - wordmarkWidth / 2,
            y: glyphFrame.maxY + glyphHeight * 0.17,
            width: wordmarkWidth,
            height: 42
        )
        let wordmarkFont = UIFont.systemFont(ofSize: 28, weight: .semibold)
        wordmarkLayer.frame = wordmarkFrame
        wordmarkLayer.string = "NodeSeek"
        wordmarkLayer.fontSize = wordmarkFont.pointSize
        wordmarkLayer.alignmentMode = .center
        wordmarkLayer.contentsScale = UIScreen.main.scale
        wordmarkLeftLayer.frame = CGRect(
            x: wordmarkFrame.minX,
            y: wordmarkFrame.minY,
            width: wordmarkFrame.width / 2,
            height: wordmarkFrame.height
        )
        wordmarkLeftLayer.string = "Node"
        wordmarkLeftLayer.fontSize = wordmarkFont.pointSize
        wordmarkLeftLayer.alignmentMode = .right
        wordmarkLeftLayer.contentsScale = UIScreen.main.scale
        wordmarkRightLayer.frame = CGRect(
            x: wordmarkFrame.midX,
            y: wordmarkFrame.minY,
            width: wordmarkFrame.width / 2,
            height: wordmarkFrame.height
        )
        wordmarkRightLayer.string = "Seek"
        wordmarkRightLayer.fontSize = wordmarkFont.pointSize
        wordmarkRightLayer.alignmentMode = .left
        wordmarkRightLayer.contentsScale = UIScreen.main.scale

        [leftWaveLayer, nodeCoreLayer, nodeEyesLayer, brandImageLayer, rightWaveLayer, wordmarkLayer, wordmarkLeftLayer, wordmarkRightLayer].forEach {
            $0.opacity = 0
            $0.transform = CATransform3DIdentity
        }
        if let containerView {
            applyBrandColors(for: containerView.traitCollection)
        }
    }

    func wavePath(center: CGPoint, radius: CGFloat, opensToLeft: Bool) -> UIBezierPath {
        let path = UIBezierPath()
        for multiplier in [0.68, 1.0] {
            let waveRadius = radius * multiplier
            let direction: CGFloat = opensToLeft ? -1 : 1
            path.move(to: CGPoint(x: center.x, y: center.y - waveRadius))
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: center.y + waveRadius),
                controlPoint: CGPoint(x: center.x + direction * waveRadius * 0.78, y: center.y)
            )
        }
        return path
    }

    func applyBrandColors(for traitCollection: UITraitCollection) {
        let darkMode = traitCollection.userInterfaceStyle == .dark
        let coreColor = darkMode ? UIColor.white : UIColor.black
        let eyeColor = darkMode ? UIColor.black : UIColor.white
        let waveColor = darkMode ? UIColor.systemGray2 : UIColor.systemGray
        nodeCoreLayer.fillColor = coreColor.cgColor
        nodeEyesLayer.fillColor = eyeColor.cgColor
        leftWaveLayer.strokeColor = waveColor.cgColor
        rightWaveLayer.strokeColor = waveColor.cgColor
        wordmarkLayer.foregroundColor = NodeSeekSplashVector.wordmarkColor(for: traitCollection).cgColor
        wordmarkLeftLayer.foregroundColor = NodeSeekSplashVector.wordmarkColor(for: traitCollection).cgColor
        wordmarkRightLayer.foregroundColor = NodeSeekSplashVector.wordmarkColor(for: traitCollection).cgColor
    }

    func layoutLayers(in bounds: CGRect) {
        backgroundLayer.frame = bounds

        let logoFrame = aspectFitFrame(for: NodeSeekSplashVector.canvasSize, in: bounds)
        configureShapeLayer(nLeftStrokeLayer, frame: logoFrame, path: NodeSeekSplashVector.nBodyPath())
        configureShapeLayer(nDiagonalStrokeLayer, frame: logoFrame, path: NodeSeekSplashVector.nBodyPath())
        configureShapeLayer(nFinalStrokeLayer, frame: logoFrame, path: NodeSeekSplashVector.nFinalStrokePath())
        configureShapeLayer(sLayer, frame: logoFrame, path: NodeSeekSplashVector.sBodyPath())
        configureDotLayer(in: logoFrame)

        nLeftStrokeLayer.mask = strokeRevealMask(
            name: "splash.n.leftStrokeMask",
            path: NodeSeekSplashVector.nLeftStrokeRevealPath(),
            lineWidth: 104,
            in: logoFrame
        )
        nDiagonalStrokeLayer.mask = strokeRevealMask(
            name: "splash.n.diagonalStrokeMask",
            path: NodeSeekSplashVector.nDiagonalStrokeRevealPath(),
            lineWidth: 128,
            lineCap: .butt,
            in: logoFrame
        )
        nFinalStrokeLayer.mask = strokeRevealMask(
            name: "splash.n.finalStrokeMask",
            path: NodeSeekSplashVector.nFinalStrokeRevealPath(),
            lineWidth: 104,
            lineCap: .butt,
            in: logoFrame
        )
        sLayer.mask = strokeRevealMask(
            name: "splash.s.strokeMask",
            path: NodeSeekSplashVector.sStrokeRevealPath(),
            lineWidth: 146,
            in: logoFrame
        )

        if let containerView {
            applyColors(for: containerView.traitCollection)
        }
    }

    func configureShapeLayer(_ layer: CAShapeLayer, frame: CGRect, path: CGPath) {
        layer.frame = frame
        let scale = frame.width / NodeSeekSplashVector.canvasSize.width
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        layer.path = path.copy(using: &transform)
        layer.fillRule = .evenOdd
        layer.contentsScale = UIScreen.main.scale
    }

    func configureDotLayer(in logoFrame: CGRect) {
        let scale = logoFrame.width / NodeSeekSplashVector.canvasSize.width
        let bounds = NodeSeekSplashVector.dotBounds
        let dotFrame = CGRect(
            x: logoFrame.minX + bounds.minX * scale,
            y: logoFrame.minY + bounds.minY * scale,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        dotLayer.frame = dotFrame

        var transform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)
        dotLayer.path = NodeSeekSplashVector.accentPath().copy(using: &transform)
        dotLayer.fillRule = .evenOdd
        dotLayer.contentsScale = UIScreen.main.scale
    }

    func applyColors(for traitCollection: UITraitCollection) {
        backgroundLayer.backgroundColor = NodeSeekSplashVector.backgroundColor(for: traitCollection).cgColor

        let wordmarkColor = NodeSeekSplashVector.wordmarkColor(for: traitCollection).cgColor
        nLeftStrokeLayer.fillColor = wordmarkColor
        nDiagonalStrokeLayer.fillColor = wordmarkColor
        nFinalStrokeLayer.fillColor = wordmarkColor
        sLayer.fillColor = wordmarkColor
        dotLayer.fillColor = NodeSeekSplashVector.accentColor.cgColor
    }

    func strokeRevealMask(
        name: String,
        path: CGPath,
        lineWidth: CGFloat,
        lineCap: CAShapeLayerLineCap = .round,
        in logoFrame: CGRect
    ) -> CAShapeLayer {
        let scale = logoFrame.width / NodeSeekSplashVector.canvasSize.width
        let mask = CAShapeLayer()
        mask.name = name
        mask.frame = CGRect(origin: .zero, size: logoFrame.size)
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        mask.path = path.copy(using: &transform)
        mask.fillColor = UIColor.clear.cgColor
        mask.strokeColor = UIColor.black.cgColor
        mask.lineWidth = lineWidth * scale
        mask.lineCap = lineCap
        mask.lineJoin = .round
        mask.strokeStart = 0
        mask.strokeEnd = 0
        return mask
    }

    func aspectFitFrame(for sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private extension NodeSeekSplashAnimator {
    func startAnimationTimeline() {
        let timelineBegin = CACurrentMediaTime()
        animateBrandLayer(leftWaveLayer, beginTime: timelineBegin, duration: 0.28)
        animateBrandLayer(rightWaveLayer, beginTime: timelineBegin + 0.10, duration: 0.28)
        animateBrandLayer(nodeCoreLayer, beginTime: timelineBegin + 0.26, duration: 0.30)
        animateBrandLayer(nodeEyesLayer, beginTime: timelineBegin + 0.46, duration: 0.22)
        animateBrandLayer(brandImageLayer, beginTime: timelineBegin + 0.30, duration: 0.34)
        animateConvergingWordmarkLayer(
            wordmarkLeftLayer,
            translationX: -containerViewWidth * 0.62,
            beginTime: timelineBegin + 0.66,
            duration: 0.38
        )
        animateConvergingWordmarkLayer(
            wordmarkRightLayer,
            translationX: containerViewWidth * 0.62,
            beginTime: timelineBegin + 0.66,
            duration: 0.38
        )
        animateBrandLayer(wordmarkLayer, beginTime: timelineBegin + 1.02, duration: 0.12)
        animateWordmarkSegmentExit(wordmarkLeftLayer, beginTime: timelineBegin + 1.02, duration: 0.12)
        animateWordmarkSegmentExit(wordmarkRightLayer, beginTime: timelineBegin + 1.02, duration: 0.12)

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self else { return }
            self.pinModelLayersToFinalFrame()
            self.complete()
        }
    }

    func pinModelLayersToFinalFrame() {
        [leftWaveLayer, nodeCoreLayer, nodeEyesLayer, brandImageLayer, rightWaveLayer, wordmarkLayer].forEach {
            $0.opacity = 1
            $0.transform = CATransform3DIdentity
            $0.removeAllAnimations()
        }
        [wordmarkLeftLayer, wordmarkRightLayer].forEach {
            $0.opacity = 0
            $0.transform = CATransform3DIdentity
            $0.removeAllAnimations()
        }
    }

    func complete() {
        completion?()
        completion = nil
    }

    func animateStrokeReveal(mask: CALayer?, beginTime: CFTimeInterval, duration: CFTimeInterval) {
        guard let mask = mask as? CAShapeLayer else { return }
        mask.strokeEnd = 0

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.beginTime = beginTime
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        mask.add(animation, forKey: "strokeReveal")
    }

    func revealStrokeMask(_ mask: CALayer?) {
        guard let mask = mask as? CAShapeLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.strokeEnd = 1
        mask.removeAnimation(forKey: "strokeReveal")
        CATransaction.commit()
    }

    func animateDotPop(beginTime: CFTimeInterval, duration: CFTimeInterval) {
        dotLayer.opacity = 1

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1]
        opacity.keyTimes = [0, 0.25, 1]
        opacity.beginTime = beginTime
        opacity.duration = duration
        opacity.fillMode = .backwards
        opacity.isRemovedOnCompletion = true
        dotLayer.add(opacity, forKey: "dotOpacity")

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.72, 1.12, 1.0]
        scale.keyTimes = [0, 0.62, 1]
        scale.beginTime = beginTime
        scale.duration = duration
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        dotLayer.add(scale, forKey: "dotPop")
    }

    func animateBrandLayer(_ layer: CALayer, beginTime: CFTimeInterval, duration: CFTimeInterval) {
        layer.opacity = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.beginTime = beginTime
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "brandFade")
    }

    var containerViewWidth: CGFloat {
        max(containerView?.bounds.width ?? 0, 1)
    }

    func animateConvergingWordmarkLayer(
        _ layer: CALayer,
        translationX: CGFloat,
        beginTime: CFTimeInterval,
        duration: CFTimeInterval
    ) {
        animateBrandLayer(layer, beginTime: beginTime, duration: duration * 0.55)
        let translation = CABasicAnimation(keyPath: "transform.translation.x")
        translation.fromValue = translationX
        translation.toValue = 0
        translation.beginTime = beginTime
        translation.duration = duration
        translation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        translation.fillMode = .both
        translation.isRemovedOnCompletion = false
        layer.add(translation, forKey: "wordmarkConvergence")
    }

    func animateWordmarkSegmentExit(_ layer: CALayer, beginTime: CFTimeInterval, duration: CFTimeInterval) {
        layer.opacity = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = beginTime
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "wordmarkSegmentExit")
    }

}
