//
//  SpectrumEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import AppKit
import simd
import Combine

class SpectrumEffect: NSObject {

    // MARK: - Properties

    private let binCount   = 96
    private let barSpacing: CGFloat = 4
    private var sceneSize: CGSize
    private var settings: LayerSettings

    private var smoothed:        [Float] = Array(repeating: 0, count: 96)
    private var renderedHeight:  [Float] = Array(repeating: 0, count: 96)
    private var lastTickTime:    TimeInterval = 0
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool = true
    var opacity: Float  = 1.0

    private var isStopped  = false
    private var wasVisible = true  // tracks last visibility to clear data on hide

    weak var renderer: EffectsRenderer?
    var rendererID: ObjectIdentifier?

    private var spectrumSettings: SpectrumSettings {
        settings.effectSettings as? SpectrumSettings ?? .defaults
    }

    // MARK: - Initialization

    init(size: CGSize, settings: LayerSettings, screen: NSScreen) {
        self.sceneSize = size
        self.settings  = settings
        self.opacity   = Float(settings.opacity)
        self.isVisible = settings.isVisible
        super.init()
        // findRenderer FIRST so subscribeToAudio receives on renderer.renderQueue.
        findRenderer(for: screen)
        subscribeToAudio()
        observeSettings()
    }

    private func findRenderer(for screen: NSScreen) {
        renderer = EffectsRendererRegistry.shared.renderer(for: screen)
        let id = ObjectIdentifier(self)
        rendererID = id
        renderer?.registerTickClient(id: id, tick: { [weak self] t in self?.tick(timestamp: t) })
    }

    func stop() {
        isStopped = true
        if let id = rendererID {
            renderer?.unregisterTickClient(id: id)
            renderer?.removeSpectrum(id: id)
        }
    }

    deinit { stop() }

    // MARK: - Observation

    private func observeSettings() {
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.opacity   = Float(self.settings.opacity)
                self.isVisible = self.settings.isVisible
            }
            .store(in: &cancellables)
    }

    private func subscribeToAudio() {
        // Same queue as renderer's tick — no locks, no main-thread dependency.
        let queue: DispatchQueue = renderer?.renderQueue ?? .main
        AudioDataBus.shared.spectrumPublisher
            .receive(on: queue)
            .sink { [weak self] bins in self?.onAudioBins(bins) }
            .store(in: &cancellables)

        AudioDataBus.shared.resetPublisher
            .receive(on: queue)
            .sink { [weak self] _ in
                guard let self else { return }
                self.smoothed       = Array(repeating: 0, count: self.binCount)
                self.renderedHeight = Array(repeating: 0, count: self.binCount)
                self.lastTickTime   = 0
            }
            .store(in: &cancellables)
    }

    // MARK: - Tick

    func tick(timestamp: TimeInterval) {
        guard !isStopped else { return }
        guard isVisible else {
            if wasVisible, let id = rendererID {
                renderer?.removeSpectrum(id: id)
                wasVisible = false
            }
            return
        }
        wasVisible = true
        guard let renderer, let id = rendererID else { return }

        // Apply power curve to audio target first (matches SKAction.resize order in SpriteKit),
        // then lerp renderedHeight toward the curved target with a 50ms time constant.
        let dt = lastTickTime == 0 ? 0.016 : min(timestamp - lastTickTime, 0.1)
        lastTickTime = timestamp
        let lerpRate = Float(1.0 - exp(-dt / 0.05))
        let powerCurve = Float(spectrumSettings.powerCurve)
        for i in 0..<binCount {
            let target = pow(smoothed[i], powerCurve)
            renderedHeight[i] += (target - renderedHeight[i]) * lerpRate
        }

        renderer.updateSpectrum(id: id, data: TrailData(vertices: buildVertices()))
    }

    // MARK: - Audio

    private func selectedBins(from stereo: StereoBins) -> [Float] {
        switch settings.channelMode {
        case .stereo:
            let half = binCount / 2
            return Array(stereo.left.prefix(half)) + Array(stereo.right.prefix(half).reversed())
        case .left:
            return Array(stereo.left.prefix(binCount))
        case .right:
            return Array(stereo.right.prefix(binCount))
        case .mono:
            return zip(stereo.left.prefix(binCount), stereo.right.prefix(binCount)).map { ($0 + $1) / 2 }
        }
    }

    private func onAudioBins(_ bins: StereoBins) {
        let ss       = spectrumSettings
        let selected = selectedBins(from: bins)
        for i in 0..<smoothed.count {
            guard i < selected.count else { break }
            let coeff    = selected[i] > smoothed[i] ? Float(ss.attack) : Float(ss.release)
            smoothed[i]  = smoothed[i] * (1 - coeff) + selected[i] * coeff
        }
    }

    // MARK: - Vertex Building

    private func buildVertices() -> [TrailVertex] {
        let ss     = spectrumSettings
        let curved = renderedHeight  // already power-curved in tick()
        let gain   = CGFloat(ss.gain)
        let half   = binCount / 2

        var vertices: [TrailVertex] = []
        vertices.reserveCapacity(binCount * 4 + (binCount - 1) * 3)

        switch ss.anchor {
        case .bottom, .top:
            let totalWidth = sceneSize.width * CGFloat(ss.width)
            let barWidth   = max(1, (totalWidth - barSpacing * CGFloat(binCount - 1)) / CGFloat(binCount))
            let leftEdgeX  = (sceneSize.width - totalWidth) * CGFloat(settings.positionX)
            let baseY      = sceneSize.height * CGFloat(settings.positionY)
            let maxH       = sceneSize.height * CGFloat(ss.maxHeight)

            for i in 0..<binCount {
                let barH     = max(1, min(CGFloat(curved[i]) * maxH * gain, maxH))
                let barLeft  = Float(leftEdgeX + CGFloat(i) * (barWidth + barSpacing))
                let barRight = barLeft + Float(barWidth)
                let isRight  = settings.channelMode == .stereo && i >= half
                let color    = barColorSIMD(for: i, value: curved[i], isRight: isRight)

                let (baseYF, tipYF): (Float, Float)
                if ss.anchor == .bottom {
                    baseYF = Float(baseY)
                    tipYF  = Float(baseY + barH)
                } else {
                    baseYF = Float(baseY)
                    tipYF  = Float(baseY - barH)
                }

                let v0 = TrailVertex(position: SIMD2(barLeft,  baseYF), color: color, alpha: opacity, edgeDist: -1)
                let v1 = TrailVertex(position: SIMD2(barLeft,  tipYF),  color: color, alpha: opacity, edgeDist: +1)
                let v2 = TrailVertex(position: SIMD2(barRight, baseYF), color: color, alpha: opacity, edgeDist: -1)
                let v3 = TrailVertex(position: SIMD2(barRight, tipYF),  color: color, alpha: opacity, edgeDist: +1)
                appendBar(to: &vertices, v0: v0, v1: v1, v2: v2, v3: v3)
            }

        case .left, .right:
            let totalHeight = sceneSize.height * CGFloat(ss.width)
            let barHeight   = max(1, (totalHeight - barSpacing * CGFloat(binCount - 1)) / CGFloat(binCount))
            let botEdgeY    = (sceneSize.height - totalHeight) * CGFloat(settings.positionY)
            let baseX       = sceneSize.width * CGFloat(settings.positionX)
            let maxW        = sceneSize.width * CGFloat(ss.maxHeight)

            for i in 0..<binCount {
                let barW    = max(1, min(CGFloat(curved[i]) * maxW * gain, maxW))
                let barBot  = Float(botEdgeY + CGFloat(i) * (barHeight + barSpacing))
                let barTop  = barBot + Float(barHeight)
                let isRight = settings.channelMode == .stereo && i >= half
                let color   = barColorSIMD(for: i, value: curved[i], isRight: isRight)

                let (baseXF, tipXF): (Float, Float)
                if ss.anchor == .left {
                    baseXF = Float(baseX)
                    tipXF  = Float(baseX + barW)
                } else {
                    baseXF = Float(baseX)
                    tipXF  = Float(baseX - barW)
                }

                // For horizontal bars, strip order: (base,bot)→(tip,bot)→(base,top)→(tip,top)
                let v0 = TrailVertex(position: SIMD2(baseXF, barBot), color: color, alpha: opacity, edgeDist: -1)
                let v1 = TrailVertex(position: SIMD2(tipXF,  barBot), color: color, alpha: opacity, edgeDist: +1)
                let v2 = TrailVertex(position: SIMD2(baseXF, barTop), color: color, alpha: opacity, edgeDist: -1)
                let v3 = TrailVertex(position: SIMD2(tipXF,  barTop), color: color, alpha: opacity, edgeDist: +1)
                appendBar(to: &vertices, v0: v0, v1: v1, v2: v2, v3: v3)
            }
        }

        return vertices
    }

    private func appendBar(to vertices: inout [TrailVertex],
                           v0: TrailVertex, v1: TrailVertex,
                           v2: TrailVertex, v3: TrailVertex) {
        if !vertices.isEmpty {
            let lastV = vertices.last!
            vertices.append(lastV)
            vertices.append(lastV)
            vertices.append(v0)
        }
        vertices.append(contentsOf: [v0, v1, v2, v3])
    }

    // MARK: - Color Calculation (alloc-free)

    private func barColorSIMD(for index: Int, value: Float, isRight: Bool) -> SIMD4<Float> {
        let ss = spectrumSettings
        let cs: ChannelColorSettings
        if settings.channelMode == .stereo && !ss.colorSync {
            cs = isRight ? ss.rightColorSettings : ss.leftColorSettings
        } else {
            cs = ss.colorSettings
        }
        switch cs.colorMode {
        case .rainbow:
            let h = Float(0.6 - rainbowRatio(for: index) * 0.5)
            return hsbToRGBA(h: h, s: 0.8, b: 1.0, a: 1.0)
        case .gradient:
            let t  = Float(gradientRatio(for: index))
            let lo = SIMD4<Float>(Float(cs.gradientColorLow.red),  Float(cs.gradientColorLow.green),
                                  Float(cs.gradientColorLow.blue), Float(cs.gradientColorLow.alpha))
            let hi = SIMD4<Float>(Float(cs.gradientColorHigh.red), Float(cs.gradientColorHigh.green),
                                  Float(cs.gradientColorHigh.blue),Float(cs.gradientColorHigh.alpha))
            return lo + (hi - lo) * t
        case .solid:
            return SIMD4<Float>(Float(cs.solidColor.red), Float(cs.solidColor.green),
                                Float(cs.solidColor.blue), Float(cs.solidColor.alpha))
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

    private func hsbToRGBA(h: Float, s: Float, b: Float, a: Float) -> SIMD4<Float> {
        let sector = Int(h * 6) % 6
        let f = h * 6 - Float(Int(h * 6))
        let p = b * (1 - s)
        let q = b * (1 - f * s)
        let t = b * (1 - (1 - f) * s)
        let rgb: SIMD3<Float>
        switch sector {
        case 0: rgb = SIMD3(b, t, p)
        case 1: rgb = SIMD3(q, b, p)
        case 2: rgb = SIMD3(p, b, t)
        case 3: rgb = SIMD3(p, q, b)
        case 4: rgb = SIMD3(t, p, b)
        default: rgb = SIMD3(b, p, q)
        }
        return SIMD4(rgb, a)
    }
}
