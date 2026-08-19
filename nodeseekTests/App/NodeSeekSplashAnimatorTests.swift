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
        #expect(layerNames.contains("splash.nodeseek.leftWaves"))
        #expect(layerNames.contains("splash.nodeseek.rightWaves"))
        #expect(layerNames.contains("splash.nodeseek.core"))
        #expect(layerNames.contains("splash.nodeseek.eyes"))
        #expect(layerNames.contains("splash.nodeseek.wordmark"))
        #expect(layerNames.contains("splash.nodeseek.wordmark.left"))
        #expect(layerNames.contains("splash.nodeseek.wordmark.right"))
        #expect(!layerNames.contains("splash.n.leftStroke"))
        #expect(!layerNames.contains("splash.finalLogo"))
    }

    @Test func animatorConfiguresNodeAndWaveGeometry() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: false)

        animator.install(in: container)

        let layers = container.layer.sublayers ?? []
        let leftWaves = layers.first { $0.name == "splash.nodeseek.leftWaves" } as? CAShapeLayer
        let rightWaves = layers.first { $0.name == "splash.nodeseek.rightWaves" } as? CAShapeLayer
        let core = layers.first { $0.name == "splash.nodeseek.core" } as? CAShapeLayer
        let eyes = layers.first { $0.name == "splash.nodeseek.eyes" } as? CAShapeLayer
        let wordmark = layers.first { $0.name == "splash.nodeseek.wordmark" } as? CATextLayer
        let wordmarkLeft = layers.first { $0.name == "splash.nodeseek.wordmark.left" } as? CATextLayer
        let wordmarkRight = layers.first { $0.name == "splash.nodeseek.wordmark.right" } as? CATextLayer

        #expect(leftWaves?.path != nil)
        #expect(rightWaves?.path != nil)
        #expect(leftWaves?.lineCap == .round)
        #expect(rightWaves?.lineCap == .round)
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
        let left = layers.first { $0.name == "splash.nodeseek.leftWaves" }
        let right = layers.first { $0.name == "splash.nodeseek.rightWaves" }
        let core = layers.first { $0.name == "splash.nodeseek.core" }
        let eyes = layers.first { $0.name == "splash.nodeseek.eyes" }
        let wordmark = layers.first { $0.name == "splash.nodeseek.wordmark" }
        let wordmarkLeft = layers.first { $0.name == "splash.nodeseek.wordmark.left" }
        let wordmarkRight = layers.first { $0.name == "splash.nodeseek.wordmark.right" }
        let animations = [left, right, core, eyes, wordmark].compactMap {
            $0?.animation(forKey: "brandFade") as? CABasicAnimation
        }

        #expect(animations.count == 5)
        if animations.count == 5 {
            #expect(animations[0].beginTime <= animations[1].beginTime)
            #expect(animations[1].beginTime <= animations[2].beginTime)
            #expect(animations[2].beginTime <= animations[3].beginTime)
            #expect(animations[3].beginTime <= animations[4].beginTime)
        }
        #expect(wordmarkLeft?.animation(forKey: "wordmarkConvergence") != nil)
        #expect(wordmarkRight?.animation(forKey: "wordmarkConvergence") != nil)
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
        #expect(layers.first { $0.name == "splash.nodeseek.leftWaves" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.rightWaves" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.core" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.eyes" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.nodeseek.wordmark" }?.opacity == 1)
    }
}
