//
//  NodeSeekSplashAnimatorTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct NodeSeekSplashAnimatorTests {
    @Test func animatorInstallsNodeSeekBrandLayers() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: false)

        animator.install(in: container)

        let layerNames = container.layer.sublayers?.compactMap(\.name) ?? []
        #expect(layerNames.contains("splash.nodeseek.core"))
        #expect(layerNames.contains("splash.nodeseek.eyes"))
        #expect(layerNames.contains("splash.nodeseek.image"))
        #expect(layerNames.contains("splash.nodeseek.wordmark"))
        #expect(layerNames.contains("splash.nodeseek.wordmark.left"))
        #expect(layerNames.contains("splash.nodeseek.wordmark.right"))
        #expect(layerNames.contains("splash.nodeseek.leftWave"))
        #expect(layerNames.contains("splash.nodeseek.rightWave"))
        #expect(layerNames.contains("splash.nodeseek.glow"))
        #expect(!layerNames.contains("splash.n.leftStroke"))
        #expect(!layerNames.contains("splash.finalLogo"))
    }

    @Test func animatorConfiguresCleanNodeGeometry() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: false)

        animator.install(in: container)

        let layers = container.layer.sublayers ?? []
        let core = layers.first { $0.name == "splash.nodeseek.core" } as? CAShapeLayer
        let eyes = layers.first { $0.name == "splash.nodeseek.eyes" } as? CAShapeLayer
        let wordmark = layers.first { $0.name == "splash.nodeseek.wordmark" } as? CATextLayer
        let wordmarkLeft = layers.first { $0.name == "splash.nodeseek.wordmark.left" } as? CATextLayer
        let wordmarkRight = layers.first { $0.name == "splash.nodeseek.wordmark.right" } as? CATextLayer

        #expect(core?.path != nil)
        #expect(eyes?.path != nil)
        #expect(wordmark?.string as? String == "NodeSeek")
        #expect(wordmarkLeft?.string as? String == "Node")
        #expect(wordmarkRight?.string as? String == "Seek")
    }

    @Test func animatorFadesBrandLayersInSequence() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: false)

        animator.install(in: container)
        animator.play {}

        let layers = container.layer.sublayers ?? []
        let core = layers.first { $0.name == "splash.nodeseek.core" }
        let eyes = layers.first { $0.name == "splash.nodeseek.eyes" }
        let brandImage = layers.first { $0.name == "splash.nodeseek.image" }
        let wordmark = layers.first { $0.name == "splash.nodeseek.wordmark" }
        let wordmarkLeft = layers.first { $0.name == "splash.nodeseek.wordmark.left" }
        let wordmarkRight = layers.first { $0.name == "splash.nodeseek.wordmark.right" }
        let animations = [core, eyes, wordmark, brandImage].compactMap {
            $0?.animation(forKey: "brandFade") as? CABasicAnimation
        }

        #expect(animations.count == 4)
        if animations.count == 4 {
            #expect(animations[0].beginTime <= animations[3].beginTime)
            #expect(animations[3].beginTime <= animations[1].beginTime)
            #expect(animations[1].beginTime <= animations[2].beginTime)
        }
        #expect(layers.first { $0.name == "splash.nodeseek.leftWave" }?.animation(forKey: "waveConvergence") != nil)
        #expect(layers.first { $0.name == "splash.nodeseek.rightWave" }?.animation(forKey: "waveConvergence") != nil)
        #expect(layers.first { $0.name == "splash.nodeseek.glow" }?.animation(forKey: "glowFade") != nil)
        #expect(wordmarkLeft?.animation(forKey: "wordmarkConvergence") != nil)
        #expect(wordmarkRight?.animation(forKey: "wordmarkConvergence") != nil)
        #expect(wordmarkLeft?.animation(forKey: "wordmarkSegmentExit") != nil)
        #expect(wordmarkRight?.animation(forKey: "wordmarkSegmentExit") != nil)
    }

    @Test func reduceMotionCompletesWithoutLongAnimation() async {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: true)
        var completed = false

        animator.install(in: container)
        animator.play {
            completed = true
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(completed)
    }

    @Test func animatorKeepsBrandLayersVisibleAtFinalFrame() async {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: false, animationDuration: 0.01)
        var completed = false

        animator.install(in: container)
        animator.play {
            completed = true
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        let layers = container.layer.sublayers ?? []
        #expect(completed)
        #expect(layers.first { $0.name == "splash.nodeseek.leftWave" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.rightWave" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.glow" }?.opacity == 0.85)
        #expect(layers.first { $0.name == "splash.nodeseek.core" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.eyes" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.image" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.wordmark" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.wordmark.left" }?.opacity == 0)
        #expect(layers.first { $0.name == "splash.nodeseek.wordmark.right" }?.opacity == 0)
    }
}
