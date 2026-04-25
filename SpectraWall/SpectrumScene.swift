//
//  TestScene.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SpriteKit
import Combine

class SpectrumScene: SKScene {
    private var bars: [SKSpriteNode] = []
    private var cancellables = Set<AnyCancellable>()

    private let binCount = 32
    private let barSpacing: CGFloat = 4

    override func didMove(to view: SKView) {
        setupBars()
        subscribeToAudio()
    }

    // MARK: - Setup

    private func setupBars() {
        let totalSpacing = barSpacing * CGFloat(binCount - 1)
        let barWidth = (size.width - totalSpacing) / CGFloat(binCount)

        for i in 0..<binCount {
            let bar = SKSpriteNode(color: .white, size: CGSize(width: barWidth, height: 2))
            let x = barWidth / 2 + CGFloat(i) * (barWidth + barSpacing)
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.position = CGPoint(x: x, y: 0)
            addChild(bar)
            bars.append(bar)
        }
    }

    // MARK: - Audio Subscription

    private func subscribeToAudio() {
        AudioDataBus.shared.spectrumPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bins in
                self?.updateBars(bins: bins)
            }
            .store(in: &cancellables)
    }

    // MARK: - Update

    private func updateBars(bins: [Float]) {
        let maxHeight = size.height * 0.8

        for (i, bar) in bars.enumerated() {
            guard i < bins.count else { break }
            let targetHeight = max(2, CGFloat(bins[i]) * maxHeight)
            bar.run(.resize(toHeight: targetHeight, duration: 0.05))

            // 低頻暖色 → 高頻冷色
            let ratio = CGFloat(i) / CGFloat(binCount)
            let color = NSColor(hue: 0.6 - ratio * 0.5, saturation: 0.8, brightness: 1.0, alpha: 1.0)
            bar.color = color
        }
    }
}
