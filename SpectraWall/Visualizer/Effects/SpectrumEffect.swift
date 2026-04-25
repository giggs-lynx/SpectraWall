//
//  TestScene.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SpriteKit
import Combine

class SpectrumEffect: SKNode {
    private var bars: [SKSpriteNode] = []
    private var cancellables = Set<AnyCancellable>()
    private var smoothed: [Float] = Array(repeating: 0, count: 96)
    private let binCount = 96
    private let barSpacing: CGFloat = 4
    private var sceneSize: CGSize = .zero
    private var settings: LayerSettings

    init(size: CGSize, settings: LayerSettings) {
        self.sceneSize = size
        self.settings = settings
        super.init()
        setupBars()
        subscribeToAudio()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupBars() {
        bars.forEach { $0.removeFromParent() }
        bars = []

        let totalSpacing = barSpacing * CGFloat(binCount - 1)
        let barWidth = (sceneSize.width - totalSpacing) / CGFloat(binCount)

        for i in 0..<binCount {
            let bar = SKSpriteNode(color: .white, size: CGSize(width: barWidth, height: 2))
            let x = barWidth / 2 + CGFloat(i) * (barWidth + barSpacing)
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.position = CGPoint(x: x, y: 0)
            addChild(bar)
            bars.append(bar)
        }
    }

    // MARK: - Audio

    private func subscribeToAudio() {
        AudioDataBus.shared.spectrumPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bins in
                self?.updateBars(bins: bins)
            }
            .store(in: &cancellables)

        AudioDataBus.shared.resetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reset()
            }
            .store(in: &cancellables)
    }

    private func selectedBins(from stereo: StereoBins) -> [Float] {
        switch settings.channelMode {
        case .stereo:
            let half = binCount / 2
            return Array(stereo.left.prefix(half)) + Array(stereo.right.prefix(half))
        case .left:
            return stereo.left
        case .right:
            return stereo.right
        case .mono:
            return zip(stereo.left, stereo.right).map { ($0 + $1) / 2 }
        }
    }

    private func updateBars(bins: StereoBins) {
        guard isHidden == false else { return }
        let selected = selectedBins(from: bins)
        let maxHeight = sceneSize.height * 0.75
        let gain = CGFloat(settings.spectrumGain)

        for i in 0..<smoothed.count {
            guard i < selected.count else { break }
            let coeff = selected[i] > smoothed[i]
                ? Float(settings.spectrumAttack)
                : Float(settings.spectrumRelease)
            smoothed[i] = smoothed[i] * (1 - coeff) + selected[i] * coeff
        }

        let curved = smoothed.map { pow($0, Float(settings.spectrumPowerCurve)) }

        for (i, bar) in bars.enumerated() {
            guard i < curved.count else { break }
            let targetHeight = max(2, min(CGFloat(curved[i]) * maxHeight * gain, maxHeight))
            bar.run(.resize(toHeight: targetHeight, duration: 0.05))

            let ratio = CGFloat(i) / CGFloat(binCount)
            let color = NSColor(hue: 0.6 - ratio * 0.5, saturation: 0.8, brightness: 1.0, alpha: 1.0)
            bar.color = color
        }
    }

    func reset() {
        smoothed = Array(repeating: 0, count: binCount)
        bars.forEach { $0.run(.resize(toHeight: 2, duration: 0.3)) }
    }
}
