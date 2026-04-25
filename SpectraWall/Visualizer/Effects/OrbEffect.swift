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

    private let baseRadius: CGFloat = 120

    init(size: CGSize, settings: LayerSettings) {
        self.sceneSize = size
        self.settings = settings
        super.init()
        setupOrb()
        subscribeToAudio()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupOrb() {
        let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)

        let glow = SKShapeNode(circleOfRadius: baseRadius * 1.4)
        glow.fillColor = NSColor(hue: 0.6, saturation: 0.8, brightness: 1.0, alpha: 0.15)
        glow.strokeColor = .clear
        glow.position = center
        glow.blendMode = .add
        addChild(glow)
        glowOrb = glow

        let main = SKShapeNode(circleOfRadius: baseRadius)
        main.fillColor = NSColor(hue: 0.6, saturation: 0.6, brightness: 1.0, alpha: 0.9)
        main.strokeColor = NSColor(hue: 0.6, saturation: 0.4, brightness: 1.0, alpha: 0.6)
        main.lineWidth = 2
        main.position = center
        main.blendMode = .add
        addChild(main)
        orb = main
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

    private func updateOrb(amplitude: Float) {
        guard isHidden == false else { return }
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
        guard bins.count > 4 else { return }
        let lowFreq = CGFloat(bins[0...3].reduce(0, +) / 4)
        let hue = 0.5 + lowFreq * 0.3

        orb?.fillColor = NSColor(hue: hue, saturation: 0.6, brightness: 1.0, alpha: 0.9)
        glowOrb?.fillColor = NSColor(hue: hue, saturation: 0.8, brightness: 1.0, alpha: 0.15)
    }

    func reset() {
        smoothedAmplitude = 0
        orb?.run(SKAction.scale(to: 1.0, duration: 0.3))
        glowOrb?.run(SKAction.scale(to: 1.0, duration: 0.3))
    }
}
