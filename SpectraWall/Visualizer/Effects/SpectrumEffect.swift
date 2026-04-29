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

    private var spectrumSettings: SpectrumSettings {
        settings.effectSettings as? SpectrumSettings ?? .defaults
    }

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

        switch spectrumSettings.anchor {
        case .bottom, .top:
            setupHorizontalBars()
        case .left, .right:
            setupVerticalBars()
        }
        updateLayout()
    }

    private func updateLayout() {
        let ss = spectrumSettings
        let totalWidth = sceneSize.width * CGFloat(ss.width)
        let startX = (sceneSize.width - totalWidth) * CGFloat(settings.positionX)
        let totalSpacing = barSpacing * CGFloat(binCount - 1)
        let barWidth = (totalWidth - totalSpacing) / CGFloat(binCount)
        let startY = sceneSize.height * CGFloat(settings.positionY)

        let totalHeight = sceneSize.height * CGFloat(ss.width)
        let startYVert = (sceneSize.height - totalHeight) * CGFloat(settings.positionY)
        let totalSpacingVert = barSpacing * CGFloat(binCount - 1)
        let barHeight = (totalHeight - totalSpacingVert) / CGFloat(binCount)
        let startXVert = sceneSize.width * CGFloat(settings.positionX)

        for (i, bar) in bars.enumerated() {
            if ss.anchor == .bottom || ss.anchor == .top {
                let x = startX + barWidth / 2 + CGFloat(i) * (barWidth + barSpacing)
                bar.position = CGPoint(x: x, y: startY)
            } else {
                let y = startYVert + barHeight / 2 + CGFloat(i) * (barHeight + barSpacing)
                bar.position = CGPoint(x: startXVert, y: y)
            }
        }
        alpha = CGFloat(settings.opacity)
    }

    private func setupHorizontalBars() {
        let ss = spectrumSettings
        let totalWidth = sceneSize.width * CGFloat(ss.width)
        let startX = (sceneSize.width - totalWidth) * CGFloat(settings.positionX)
        let totalSpacing = barSpacing * CGFloat(binCount - 1)
        let barWidth = (totalWidth - totalSpacing) / CGFloat(binCount)
        let startY = sceneSize.height * CGFloat(settings.positionY)

        for i in 0..<binCount {
            let bar = SKSpriteNode(color: .white, size: CGSize(width: barWidth, height: 2))
            let x = startX + barWidth / 2 + CGFloat(i) * (barWidth + barSpacing)
            bar.anchorPoint = ss.anchor == .bottom
                ? CGPoint(x: 0.5, y: 0)
                : CGPoint(x: 0.5, y: 1)
            bar.position = CGPoint(x: x, y: startY)
            addChild(bar)
            bars.append(bar)
        }
    }

    private func setupVerticalBars() {
        let ss = spectrumSettings
        let totalHeight = sceneSize.height * CGFloat(ss.width)
        let startY = (sceneSize.height - totalHeight) * CGFloat(settings.positionY)
        let totalSpacing = barSpacing * CGFloat(binCount - 1)
        let barHeight = (totalHeight - totalSpacing) / CGFloat(binCount)
        let startX = sceneSize.width * CGFloat(settings.positionX)

        for i in 0..<binCount {
            let bar = SKSpriteNode(color: .white, size: CGSize(width: 2, height: barHeight))
            let y = startY + barHeight / 2 + CGFloat(i) * (barHeight + barSpacing)
            bar.anchorPoint = ss.anchor == .left
                ? CGPoint(x: 0, y: 0.5)
                : CGPoint(x: 1, y: 0.5)
            bar.position = CGPoint(x: startX, y: y)
            addChild(bar)
            bars.append(bar)
        }
    }

    // MARK: - Observe Settings

    private func observeSettings() {
        var lastAnchor = spectrumSettings.anchor
        var lastWidth = spectrumSettings.width
        
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                let currentSettings = self.spectrumSettings
                
                if currentSettings.anchor != lastAnchor || 
                   currentSettings.width != lastWidth {
                    lastAnchor = currentSettings.anchor
                    lastWidth = currentSettings.width
                    self.setupBars()
                } else {
                    self.updateLayout()
                }
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
        let ss = spectrumSettings
        let selected = selectedBins(from: bins)

        for i in 0..<smoothed.count {
            guard i < selected.count else { break }
            let coeff = selected[i] > smoothed[i]
                ? Float(ss.attack)
                : Float(ss.release)
            smoothed[i] = smoothed[i] * (1 - coeff) + selected[i] * coeff
        }

        let curved = smoothed.map { pow($0, Float(ss.powerCurve)) }

        switch ss.anchor {
        case .bottom, .top:
            updateHorizontalBars(curved: curved)
        case .left, .right:
            updateVerticalBars(curved: curved)
        }
    }

    private func updateHorizontalBars(curved: [Float]) {
        let ss = spectrumSettings
        let maxHeight = sceneSize.height * CGFloat(ss.maxHeight)
        let gain = CGFloat(ss.gain)
        let half = binCount / 2

        for (i, bar) in bars.enumerated() {
            guard i < curved.count else { break }
            let targetHeight = max(2, min(CGFloat(curved[i]) * maxHeight * gain, maxHeight))
            bar.run(.resize(toHeight: targetHeight, duration: 0.05))
            bar.color = barColor(for: i, value: curved[i], isRightChannel: i >= half)
        }
    }

    private func updateVerticalBars(curved: [Float]) {
        let ss = spectrumSettings
        let maxWidth = sceneSize.width * CGFloat(ss.maxHeight)
        let gain = CGFloat(ss.gain)
        let half = binCount / 2

        for (i, bar) in bars.enumerated() {
            guard i < curved.count else { break }
            let targetWidth = max(2, min(CGFloat(curved[i]) * maxWidth * gain, maxWidth))
            bar.run(.resize(toWidth: targetWidth, duration: 0.05))
            bar.color = barColor(for: i, value: curved[i], isRightChannel: i >= half)
        }
    }

    private func barColor(for index: Int, value: Float, isRightChannel: Bool = false) -> NSColor {
        let ss = spectrumSettings
        let colorSettings: ChannelColorSettings

        if settings.channelMode == .stereo && !ss.colorSync {
            colorSettings = isRightChannel ? ss.rightColorSettings : ss.leftColorSettings
        } else {
            colorSettings = ss.colorSettings
        }

        switch colorSettings.colorMode {
        case .rainbow:
            if settings.channelMode == .stereo {
                let half = binCount / 2
                let ratio: CGFloat
                if index < half {
                    ratio = CGFloat(index) / CGFloat(half - 1)
                } else {
                    let originalRatio = CGFloat(index - half) / CGFloat(half - 1)
                    ratio = 1.0 - originalRatio
                }
                return NSColor(hue: 0.6 - ratio * 0.5, saturation: 0.8, brightness: 1.0, alpha: 1.0)
            } else {
                let ratio = CGFloat(index) / CGFloat(binCount)
                return NSColor(hue: 0.6 - ratio * 0.5, saturation: 0.8, brightness: 1.0, alpha: 1.0)
            }

        case .gradient:
            let ratio: CGFloat
            if settings.channelMode == .stereo {
                let half = binCount / 2
                if index < half {
                    ratio = CGFloat(index) / CGFloat(half - 1)
                } else {
                    let originalRatio = CGFloat(index - half) / CGFloat(half - 1)
                    ratio = 1.0 - originalRatio
                }
            } else {
                ratio = CGFloat(index) / CGFloat(binCount - 1)
            }
            return interpolateColor(
                from: colorSettings.gradientColorLow.nsColor,
                to: colorSettings.gradientColorHigh.nsColor,
                t: ratio
            )

        case .solid:
            return colorSettings.solidColor.nsColor
        }
    }

    private func interpolateColor(from: NSColor, to: NSColor, t: CGFloat) -> NSColor {
        let r = from.redComponent + (to.redComponent - from.redComponent) * t
        let g = from.greenComponent + (to.greenComponent - from.greenComponent) * t
        let b = from.blueComponent + (to.blueComponent - from.blueComponent) * t
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    func reset() {
        smoothed = Array(repeating: 0, count: binCount)
        switch spectrumSettings.anchor {
        case .bottom, .top:
            bars.forEach { $0.run(.resize(toHeight: 2, duration: 0.3)) }
        case .left, .right:
            bars.forEach { $0.run(.resize(toWidth: 2, duration: 0.3)) }
        }
    }
}
