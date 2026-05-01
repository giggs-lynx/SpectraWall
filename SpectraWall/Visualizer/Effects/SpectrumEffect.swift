//
//  SpectrumEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SpriteKit
import Combine

class SpectrumEffect: SKNode {

    // MARK: - Properties (Nodes & State)

    private var bars: [SKSpriteNode] = []
    private var smoothed: [Float] = Array(repeating: 0, count: 96)
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Properties (Configuration)

    private let binCount = 96
    private let barSpacing: CGFloat = 4
    private var sceneSize: CGSize = .zero
    private var settings: LayerSettings

    private var spectrumSettings: SpectrumSettings {
        settings.effectSettings as? SpectrumSettings ?? .defaults
    }

    // MARK: - Initialization

    init(size: CGSize, settings: LayerSettings) {
        self.sceneSize = size
        self.settings = settings
        super.init()

        setupBars()
        subscribeToAudio()
        observeSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle & Observation

    private func observeSettings() {
        var lastAnchor = spectrumSettings.anchor
        var lastWidth  = spectrumSettings.width

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let current = self.spectrumSettings
                if current.anchor != lastAnchor || current.width != lastWidth {
                    lastAnchor = current.anchor
                    lastWidth  = current.width
                    self.setupBars()
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

    // MARK: - Setup & Layout

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
        let ss  = spectrumSettings
        let pos = settings

        let totalWidth  = sceneSize.width  * CGFloat(ss.width)
        let startX      = (sceneSize.width - totalWidth) * CGFloat(pos.positionX)
        let startY      = sceneSize.height * CGFloat(pos.positionY)

        let totalHeight = sceneSize.height * CGFloat(ss.width)
        let startYVert  = (sceneSize.height - totalHeight) * CGFloat(pos.positionY)
        let startXVert  = sceneSize.width * CGFloat(pos.positionX)

        for (i, bar) in bars.enumerated() {
            if ss.anchor == .bottom || ss.anchor == .top {
                let barWidth = bar.size.width
                let x = startX + barWidth / 2 + CGFloat(i) * (barWidth + barSpacing)
                bar.position = CGPoint(x: x, y: startY)
            } else {
                let barHeight = bar.size.height
                let y = startYVert + barHeight / 2 + CGFloat(i) * (barHeight + barSpacing)
                bar.position = CGPoint(x: startXVert, y: y)
            }
        }

        alpha = CGFloat(settings.opacity)
    }

    private func setupHorizontalBars() {
        let ss       = spectrumSettings
        let total    = sceneSize.width * CGFloat(ss.width)
        let barWidth = max(1, (total - barSpacing * CGFloat(binCount - 1)) / CGFloat(binCount))

        bars = (0..<binCount).map { _ in
            let bar = SKSpriteNode(color: .white, size: CGSize(width: barWidth, height: 2))
            bar.anchorPoint = ss.anchor == .bottom ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0.5, y: 1)
            bar.position = .zero
            addChild(bar)
            return bar
        }
    }

    private func setupVerticalBars() {
        let ss        = spectrumSettings
        let total     = sceneSize.height * CGFloat(ss.width)
        let barHeight = max(1, (total - barSpacing * CGFloat(binCount - 1)) / CGFloat(binCount))

        bars = (0..<binCount).map { _ in
            let bar = SKSpriteNode(color: .white, size: CGSize(width: 2, height: barHeight))
            bar.anchorPoint = ss.anchor == .left ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 1, y: 0.5)
            bar.position = .zero
            addChild(bar)
            return bar
        }
    }

    // MARK: - Audio Processing

    private func selectedBins(from stereo: StereoBins) -> [Float] {
        switch settings.channelMode {
        case .stereo:
            let half      = binCount / 2
            let leftBins  = Array(stereo.left.prefix(half))
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

        let ss       = spectrumSettings
        let selected = selectedBins(from: bins)

        for i in 0..<smoothed.count {
            guard i < selected.count else { break }
            let coeff    = selected[i] > smoothed[i] ? Float(ss.attack) : Float(ss.release)
            smoothed[i]  = smoothed[i] * (1 - coeff) + selected[i] * coeff
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
        let ss        = spectrumSettings
        let maxHeight = sceneSize.height * CGFloat(ss.maxHeight)
        let gain      = CGFloat(ss.gain)
        let half      = binCount / 2

        for (i, bar) in bars.enumerated() {
            guard i < curved.count else { break }
            let barHeight = max(2, min(CGFloat(curved[i]) * maxHeight * gain, maxHeight))
            bar.run(.resize(toHeight: barHeight, duration: 0.05))
            bar.color = barColor(for: i, value: curved[i], isRightChannel: i >= half)
        }
    }

    private func updateVerticalBars(curved: [Float]) {
        let ss       = spectrumSettings
        let maxWidth = sceneSize.width * CGFloat(ss.maxHeight)
        let gain     = CGFloat(ss.gain)
        let half     = binCount / 2

        for (i, bar) in bars.enumerated() {
            guard i < curved.count else { break }
            let barWidth = max(2, min(CGFloat(curved[i]) * maxWidth * gain, maxWidth))
            bar.run(.resize(toWidth: barWidth, duration: 0.05))
            bar.color = barColor(for: i, value: curved[i], isRightChannel: i >= half)
        }
    }

    // MARK: - Color Calculation

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
            let ratio = rainbowRatio(for: index)
            return NSColor(hue: 0.6 - ratio * 0.5, saturation: 0.8, brightness: 1.0, alpha: 1.0)

        case .gradient:
            let ratio = gradientRatio(for: index)
            return interpolateColor(
                from: colorSettings.gradientColorLow.nsColor,
                to: colorSettings.gradientColorHigh.nsColor,
                progress: ratio
            )

        case .solid:
            return colorSettings.solidColor.nsColor
        }
    }

    private func rainbowRatio(for index: Int) -> CGFloat {
        if settings.channelMode == .stereo {
            let half = binCount / 2
            return index < half
                ? CGFloat(index) / CGFloat(half - 1)
                : 1.0 - CGFloat(index - half) / CGFloat(half - 1)
        }
        return CGFloat(index) / CGFloat(binCount)
    }

    private func gradientRatio(for index: Int) -> CGFloat {
        if settings.channelMode == .stereo {
            let half = binCount / 2
            return index < half
                ? CGFloat(index) / CGFloat(half - 1)
                : 1.0 - CGFloat(index - half) / CGFloat(half - 1)
        }
        return CGFloat(index) / CGFloat(binCount - 1)
    }

    private func interpolateColor(from: NSColor, to: NSColor, progress: CGFloat) -> NSColor {
        NSColor(
            red: from.redComponent + (to.redComponent - from.redComponent) * progress,
            green: from.greenComponent + (to.greenComponent - from.greenComponent) * progress,
            blue: from.blueComponent + (to.blueComponent - from.blueComponent) * progress,
            alpha: 1.0
        )
    }

    // MARK: - Control

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
