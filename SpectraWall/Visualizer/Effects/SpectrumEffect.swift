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
        observeSettings()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupBars() {
        bars.forEach { $0.removeFromParent() }
        bars = []

        let totalWidth = sceneSize.width * CGFloat(settings.spectrumWidth)
        let startX = (sceneSize.width - totalWidth) * CGFloat(settings.positionX)
        let totalSpacing = barSpacing * CGFloat(binCount - 1)
        let barWidth = (totalWidth - totalSpacing) / CGFloat(binCount)
        let startY = sceneSize.height * CGFloat(settings.positionY)

        for i in 0..<binCount {
            let bar = SKSpriteNode(color: .white, size: CGSize(width: barWidth, height: 2))
            let x = startX + barWidth / 2 + CGFloat(i) * (barWidth + barSpacing)
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.position = CGPoint(x: x, y: startY)
            addChild(bar)
            bars.append(bar)
        }

        alpha = CGFloat(settings.opacity)
    }

    // MARK: - Observe Settings

    private func observeSettings() {
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupBars()
            }
            .store(in: &cancellables)
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
            let leftBins = Array(stereo.left.prefix(half))
            let rightBins = Array(stereo.right.prefix(half).reversed())
            return leftBins + rightBins
        case .left:
            return stereo.left
        case .right:
            return stereo.right
        case .mono:
            return zip(stereo.left, stereo.right).map { ($0 + $1) / 2 }
        }
    }

    private func updateBars(bins: StereoBins) {
        guard !isHidden else { return }
        let selected = selectedBins(from: bins)
        let maxHeight = sceneSize.height * CGFloat(settings.spectrumMaxHeight)
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
            bar.color = barColor(for: i, value: curved[i])
        }
    }

    private func barColor(for index: Int, value: Float) -> NSColor {
        switch settings.spectrumColorMode {
        case .rainbow:
            if settings.channelMode == .stereo {
                let half = binCount / 2
                let ratio: CGFloat
                
                if index < half {
                    // 左聲道：低頻 -> 高頻 (0.0 -> 1.0)
                    ratio = CGFloat(index) / CGFloat(half - 1)
                } else {
                    // 右聲道：高頻 -> 低頻
                    // 透過 (1.0 - ratio) 將顏色反轉，使其符合 高頻(暖) -> 低頻(冷)
                    let originalRatio = CGFloat(index - half) / CGFloat(half - 1)
                    ratio = 1.0 - originalRatio
                }
                return NSColor(hue: 0.6 - ratio * 0.5, saturation: 0.8, brightness: 1.0, alpha: 1.0)
            } else {
                let ratio = CGFloat(index) / CGFloat(binCount)
                return NSColor(hue: 0.6 - ratio * 0.5, saturation: 0.8, brightness: 1.0, alpha: 1.0)
            }
        case .solid:
            return settings.spectrumSolidColor.nsColor
        }
    }

    func reset() {
        smoothed = Array(repeating: 0, count: binCount)
        bars.forEach { $0.run(.resize(toHeight: 2, duration: 0.3)) }
    }
}
