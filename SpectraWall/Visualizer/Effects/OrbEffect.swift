//
//  OrbEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SpriteKit
import Combine

class OrbEffect: SKNode {
    
    // MARK: - Nodes
    
    private var orb: SKShapeNode?
    private var glowOrb: SKShapeNode?
    
    // MARK: - Properties (State & Settings)
    
    private var settings: LayerSettings
    private var cancellables = Set<AnyCancellable>()
    private var smoothedAmplitude: Float = 0
    private var sceneSize: CGSize = .zero
    
    private var orbSettings: OrbSettings {
        settings.effectSettings as? OrbSettings ?? .defaults
    }

    private let baseRadius: CGFloat = 120

    // MARK: - Initialization

    init(size: CGSize, settings: LayerSettings) {
        self.sceneSize = size
        self.settings = settings
        super.init()
        
        setupOrb()
        subscribeToAudio()
        observeSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle & Observation

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

    // MARK: - Setup & Layout

    private func setupOrb() {
        orb?.removeFromParent()
        glowOrb?.removeFromParent()

        let os = orbSettings
        let radius = CGFloat(os.baseRadius)
        
        // Setup Outer Glow
        let glow = SKShapeNode(circleOfRadius: radius * CGFloat(os.outerRadiusMultiplier))
        glow.fillColor = os.outerColorLow.nsColor.withAlphaComponent(CGFloat(os.outerOpacity))
        glow.strokeColor = .clear
        glow.blendMode = .add
        addChild(glow)
        glowOrb = glow

        // Setup Main Orb
        let main = SKShapeNode(circleOfRadius: radius)
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

    // MARK: - Audio Driven Updates

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
        let intensity = CGFloat((leftLow + rightLow) / 2)

        let innerColor = interpolateColor(
            from: os.innerColorLow.nsColor,
            to: os.innerColorHigh.nsColor,
            progress: intensity
        )
        
        let outerColor = interpolateColor(
            from: os.outerColorLow.nsColor,
            to: os.outerColorHigh.nsColor,
            progress: intensity
        )

        orb?.fillColor = innerColor
        orb?.strokeColor = innerColor.withAlphaComponent(0.6)
        glowOrb?.fillColor = outerColor.withAlphaComponent(CGFloat(os.outerOpacity))
    }

    // MARK: - Helper Methods

    private func interpolateColor(from: NSColor, to: NSColor, progress: CGFloat) -> NSColor {
        let red = from.redComponent + (to.redComponent - from.redComponent) * progress
        let green = from.greenComponent + (to.greenComponent - from.greenComponent) * progress
        let blue = from.blueComponent + (to.blueComponent - from.blueComponent) * progress
        let alpha = from.alphaComponent + (to.alphaComponent - from.alphaComponent) * progress
        
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func reset() {
        smoothedAmplitude = 0
        orb?.run(SKAction.scale(to: 1.0, duration: 0.3))
        glowOrb?.run(SKAction.scale(to: 1.0, duration: 0.3))
    }
}
