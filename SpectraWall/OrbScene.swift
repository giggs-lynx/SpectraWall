//
//  OrbScene.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SpriteKit
import Combine

class OrbScene: SKScene {
    private var orb: SKShapeNode?
    private var glowOrb: SKShapeNode?
    private var cancellables = Set<AnyCancellable>()

    private let baseRadius: CGFloat = 120
    private var currentRadius: CGFloat = 120

    override func didMove(to view: SKView) {
        setupOrb()
        subscribeToAudio()
    }
    
    private var smoothedAmplitude: Float = 0
    private let orbAttack: Float = 0.6
    private let orbRelease: Float = 0.25  // 這個調大，縮回去更快

    // MARK: - Setup

    private func setupOrb() {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Glow 層（大一點、半透明）
        let glow = SKShapeNode(circleOfRadius: baseRadius * 1.4)
        glow.fillColor = NSColor(hue: 0.6, saturation: 0.8, brightness: 1.0, alpha: 0.15)
        glow.strokeColor = .clear
        glow.position = center
        glow.blendMode = .add
        addChild(glow)
        glowOrb = glow

        // 主球
        let main = SKShapeNode(circleOfRadius: baseRadius)
        main.fillColor = NSColor(hue: 0.6, saturation: 0.6, brightness: 1.0, alpha: 0.9)
        main.strokeColor = NSColor(hue: 0.6, saturation: 0.4, brightness: 1.0, alpha: 0.6)
        main.lineWidth = 2
        main.position = center
        main.blendMode = .add
        addChild(main)
        orb = main
    }

    // MARK: - Audio Subscription

    private func subscribeToAudio() {
        AudioDataBus.shared.amplitudePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] amplitude in
                self?.updateOrb(amplitude: amplitude)
            }
            .store(in: &cancellables)

        AudioDataBus.shared.spectrumPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bins in
                self?.updateColor(bins: bins)
            }
            .store(in: &cancellables)
    }

    // MARK: - Update

    private func updateOrb(amplitude: Float) {
        let settings = VisualizerSettings.shared
        let coeff = amplitude > smoothedAmplitude
            ? Float(settings.orbAttack)
            : Float(settings.orbRelease)
        smoothedAmplitude = smoothedAmplitude * (1 - coeff) + amplitude * coeff

        let boost = CGFloat(settings.orbBoost)
        let targetScale = 1.0 + CGFloat(smoothedAmplitude) * boost
        let clampedScale = min(targetScale, 2.5)

        orb?.run(SKAction.scale(to: clampedScale, duration: 0.05))
        glowOrb?.run(SKAction.scale(to: clampedScale, duration: 0.08))
    }

    private func updateColor(bins: [Float]) {
        // 低頻驅動色相變化
        guard bins.count > 4 else { return }
        let lowFreq = CGFloat(bins[0...3].reduce(0, +) / 4)
        let hue = 0.5 + lowFreq * 0.3

        let mainColor = NSColor(hue: hue, saturation: 0.6, brightness: 1.0, alpha: 0.9)
        let glowColor = NSColor(hue: hue, saturation: 0.8, brightness: 1.0, alpha: 0.15)

        orb?.fillColor = mainColor
        glowOrb?.fillColor = glowColor
    }
}
