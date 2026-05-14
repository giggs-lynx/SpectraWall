//
//  OrbEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SpriteKit
import Combine

class OrbEffect: SKNode, UpdatableEffectNode {

    // MARK: - Nodes

    private var orb: SKShapeNode?
    private var glowOrb: SKShapeNode?

    // MARK: - Properties (State & Settings)

    private var settings: LayerSettings
    private var cancellables = Set<AnyCancellable>()

    // Separate smoothed amplitudes for left/right channels
    private var smoothedLeft: Float = 0
    private var smoothedRight: Float = 0
    private var displayedScale: CGFloat = 1.0
    private var latestBins: StereoBins?
    private var lastUpdateTime: TimeInterval = 0

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
                guard let self else { return }
                let current = self.orbSettings
                if current.baseRadius != lastBaseRadius {
                    lastBaseRadius = current.baseRadius
                    self.setupOrb()
                } else {
                    self.updateLayout()
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToAudio() {
        AudioDataBus.shared.spectrumPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bins in
                self?.latestBins = bins
            }
            .store(in: &cancellables)

        AudioDataBus.shared.resetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reset()
            }
            .store(in: &cancellables)
    }

    func update(_ currentTime: TimeInterval) {
        guard let bins = latestBins else { return }
        let dt = lastUpdateTime == 0 ? (1.0 / 94.0) : currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        updateOrb(bins: bins, dt: dt)
        updateColor(bins: bins)
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

    private func updateOrb(bins: StereoBins, dt: TimeInterval = 1.0 / 94.0) {
        guard !isHidden else { return }

        let os    = orbSettings
        let scale = dt * 94.0
        let leftAmp  = bins.leftAmplitude()
        let rightAmp = bins.rightAmplitude()

        let leftCoeff  = Float(1.0 - pow(1.0 - Double(leftAmp  > smoothedLeft  ? os.attack : os.release), scale))
        let rightCoeff = Float(1.0 - pow(1.0 - Double(rightAmp > smoothedRight ? os.attack : os.release), scale))

        smoothedLeft  = smoothedLeft  * (1 - leftCoeff)  + leftAmp  * leftCoeff
        smoothedRight = smoothedRight * (1 - rightCoeff) + rightAmp * rightCoeff

        let amplitude: Float
        switch settings.channelMode {
        case .stereo, .mono:
            amplitude = (smoothedLeft + smoothedRight) / 2
        case .left:
            amplitude = smoothedLeft
        case .right:
            amplitude = smoothedRight
        }

        let targetScale  = min(1.0 + CGFloat(amplitude) * CGFloat(os.boost), 2.5)
        let visualCoeff  = CGFloat(1.0 - pow(0.75, scale))
        displayedScale   = displayedScale * (1 - visualCoeff) + targetScale * visualCoeff
        orb?.setScale(displayedScale)
        glowOrb?.setScale(displayedScale)
    }

    private func updateColor(bins: StereoBins) {
        let os = orbSettings
        let intensity = CGFloat(bins.amplitude(for: settings.channelMode, binRange: 0..<4))

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
        let red   = from.redComponent   + (to.redComponent   - from.redComponent)   * progress
        let green = from.greenComponent + (to.greenComponent - from.greenComponent) * progress
        let blue  = from.blueComponent  + (to.blueComponent  - from.blueComponent)  * progress
        let alpha = from.alphaComponent + (to.alphaComponent - from.alphaComponent) * progress

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func reset() {
        smoothedLeft  = 0
        smoothedRight = 0
        orb?.run(SKAction.scale(to: 1.0, duration: 0.3))
        glowOrb?.run(SKAction.scale(to: 1.0, duration: 0.3))
    }
}
