//
//  OrbScene.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SpriteKit
import Combine

class OrbEffect: SKNode {
    private var orb: SKShapeNode?
    private var glowOrb: SKShapeNode?
    private var cancellables = Set<AnyCancellable>()
    private var smoothedAmplitude: Float = 0
    private var sceneSize: CGSize = .zero
    private var settings: LayerSettings

    init(size: CGSize, settings: LayerSettings) {
        self.sceneSize = size
        self.settings = settings
        super.init()
        setupOrb()
        subscribeToAudio()
        observeSettings()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupOrb() {
        orb?.removeFromParent()
        glowOrb?.removeFromParent()

        let baseRadius = CGFloat(settings.orbBaseRadius)
        let center = CGPoint(
            x: sceneSize.width * CGFloat(settings.positionX),
            y: sceneSize.height * CGFloat(settings.positionY)
        )

        let glow = SKShapeNode(circleOfRadius: baseRadius * 1.4)
        glow.fillColor = settings.orbOuterColorLow.nsColor.withAlphaComponent(CGFloat(settings.orbOuterOpacity))
        glow.strokeColor = .clear
        glow.position = center
        glow.blendMode = .add
        addChild(glow)
        glowOrb = glow

        let main = SKShapeNode(circleOfRadius: baseRadius)
        main.fillColor = settings.orbInnerColorLow.nsColor
        main.strokeColor = settings.orbInnerColorLow.nsColor.withAlphaComponent(0.6)
        main.lineWidth = 2
        main.position = center
        main.blendMode = .add
        addChild(main)
        orb = main

        alpha = CGFloat(settings.opacity)
    }

    // MARK: - Observe Settings

    private func observeSettings() {
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupOrb()
            }
            .store(in: &cancellables)
    }

    // MARK: - Audio

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

        AudioDataBus.shared.resetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reset()
            }
            .store(in: &cancellables)
    }

    private func updateOrb(amplitude: Float) {
        guard !isHidden else { return }
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

    private func updateColor(bins: StereoBins) {
        let leftLow = bins.left.prefix(4).reduce(0, +) / 4
        let rightLow = bins.right.prefix(4).reduce(0, +) / 4
        let t = CGFloat((leftLow + rightLow) / 2)

        // 在 low 和 high 顏色之間插值
        let innerColor = interpolateColor(
            from: settings.orbInnerColorLow.nsColor,
            to: settings.orbInnerColorHigh.nsColor,
            t: t
        )
        let outerColor = interpolateColor(
            from: settings.orbOuterColorLow.nsColor,
            to: settings.orbOuterColorHigh.nsColor,
            t: t
        )

        orb?.fillColor = innerColor
        orb?.strokeColor = innerColor.withAlphaComponent(0.6)
        glowOrb?.fillColor = outerColor.withAlphaComponent(CGFloat(settings.orbOuterOpacity))
    }

    private func interpolateColor(from: NSColor, to: NSColor, t: CGFloat) -> NSColor {
        let r = from.redComponent + (to.redComponent - from.redComponent) * t
        let g = from.greenComponent + (to.greenComponent - from.greenComponent) * t
        let b = from.blueComponent + (to.blueComponent - from.blueComponent) * t
        let a = from.alphaComponent + (to.alphaComponent - from.alphaComponent) * t
        return NSColor(red: r, green: g, blue: b, alpha: a)
    }

    func reset() {
        smoothedAmplitude = 0
        orb?.run(SKAction.scale(to: 1.0, duration: 0.3))
        glowOrb?.run(SKAction.scale(to: 1.0, duration: 0.3))
    }
}
