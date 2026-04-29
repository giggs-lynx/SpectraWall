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

    private var orbSettings: OrbSettings {
        settings.effectSettings as? OrbSettings ?? .defaults
    }

    private let baseRadius: CGFloat = 120

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

        let os = orbSettings
        let baseRadius = CGFloat(os.baseRadius)
        
        let glow = SKShapeNode(circleOfRadius: baseRadius * CGFloat(os.outerRadiusMultiplier))
        glow.fillColor = os.outerColorLow.nsColor.withAlphaComponent(CGFloat(os.outerOpacity))
        glow.strokeColor = .clear
        glow.blendMode = .add
        addChild(glow)
        glowOrb = glow

        let main = SKShapeNode(circleOfRadius: baseRadius)
        main.fillColor = os.innerColorLow.nsColor
        main.strokeColor = os.innerColorLow.nsColor.withAlphaComponent(0.6)
        main.lineWidth = 2
        main.blendMode = .add
        addChild(main)
        orb = main
        
        updateLayout()
    }

    private func updateLayout() {
        let center = CGPoint(
            x: sceneSize.width * CGFloat(settings.positionX),
            y: sceneSize.height * CGFloat(settings.positionY)
        )
        orb?.position = center
        glowOrb?.position = center
        alpha = CGFloat(settings.opacity)
    }

    // MARK: - Observe Settings

    private func observeSettings() {
        var lastBaseRadius = orbSettings.baseRadius
        
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                let currentSettings = self.orbSettings
                
                if currentSettings.baseRadius != lastBaseRadius {
                    lastBaseRadius = currentSettings.baseRadius
                    self.setupOrb()
                } else {
                    self.updateLayout()
                }
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
        let os = orbSettings
        let coeff = amplitude > smoothedAmplitude
            ? Float(os.attack)
            : Float(os.release)
        smoothedAmplitude = smoothedAmplitude * (1 - coeff) + amplitude * coeff

        let boost = CGFloat(os.boost)
        let targetScale = 1.0 + CGFloat(smoothedAmplitude) * boost
        let clampedScale = min(targetScale, 2.5)

        orb?.run(SKAction.scale(to: clampedScale, duration: 0.05))
        glowOrb?.run(SKAction.scale(to: clampedScale, duration: 0.08))
    }

    private func updateColor(bins: StereoBins) {
        let os = orbSettings
        let leftLow = bins.left.prefix(4).reduce(0, +) / 4
        let rightLow = bins.right.prefix(4).reduce(0, +) / 4
        let t = CGFloat((leftLow + rightLow) / 2)

        let innerColor = interpolateColor(from: os.innerColorLow.nsColor, to: os.innerColorHigh.nsColor, t: t)
        let outerColor = interpolateColor(from: os.outerColorLow.nsColor, to: os.outerColorHigh.nsColor, t: t)

        orb?.fillColor = innerColor
        orb?.strokeColor = innerColor.withAlphaComponent(0.6)
        glowOrb?.fillColor = outerColor.withAlphaComponent(CGFloat(os.outerOpacity))
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
