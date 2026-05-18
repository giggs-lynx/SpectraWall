//
//  OrbEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import AppKit
import simd
import Combine

class OrbEffect: NSObject {

    // MARK: - Properties

    private var sceneSize: CGSize
    private var settings: LayerSettings
    private var cancellables = Set<AnyCancellable>()

    private var smoothedLeft:  Float = 0
    private var smoothedRight: Float = 0

    // Derived from audio each callback; read in tick (both on main thread)
    private var currentScale:      Float = 1.0
    private var currentInnerColor: SIMD4<Float> = SIMD4(0.2, 0.4, 1.0, 1.0)
    private var currentOuterColor: SIMD4<Float> = SIMD4(0.2, 0.4, 1.0, 0.15)

    var isVisible: Bool = true
    var opacity:   Float = 1.0

    private var isStopped  = false
    private var wasVisible = true

    weak var renderer: EffectsRenderer?
    var rendererID: ObjectIdentifier?

    private var orbSettings: OrbSettings {
        settings.effectSettings as? OrbSettings ?? .defaults
    }

    private let fanSegments = 32

    // MARK: - Initialization

    init(size: CGSize, settings: LayerSettings, screen: NSScreen) {
        self.sceneSize = size
        self.settings  = settings
        self.opacity   = Float(settings.opacity)
        self.isVisible = settings.isVisible
        super.init()
        subscribeToAudio()
        observeSettings()
        findRenderer(for: screen)
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
            renderer?.removeOrb(id: id)
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
        AudioDataBus.shared.spectrumPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bins in self?.onAudioBins(bins) }
            .store(in: &cancellables)

        AudioDataBus.shared.resetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellables)
    }

    // MARK: - Tick

    func tick(timestamp: TimeInterval) {
        guard !isStopped else { return }
        guard isVisible else {
            if wasVisible, let id = rendererID {
                renderer?.removeOrb(id: id)
                wasVisible = false
            }
            return
        }
        wasVisible = true
        guard let renderer, let id = rendererID else { return }
        renderer.updateOrb(id: id, data: buildOrbData())
    }

    // MARK: - Audio

    private func onAudioBins(_ bins: StereoBins) {
        let os = orbSettings

        let leftAmp  = bins.leftAmplitude()
        let rightAmp = bins.rightAmplitude()
        let lCoeff   = leftAmp  > smoothedLeft  ? Float(os.attack) : Float(os.release)
        let rCoeff   = rightAmp > smoothedRight ? Float(os.attack) : Float(os.release)
        smoothedLeft  = smoothedLeft  * (1 - lCoeff) + leftAmp  * lCoeff
        smoothedRight = smoothedRight * (1 - rCoeff) + rightAmp * rCoeff

        let amplitude: Float
        switch settings.channelMode {
        case .stereo, .mono: amplitude = (smoothedLeft + smoothedRight) / 2
        case .left:          amplitude = smoothedLeft
        case .right:         amplitude = smoothedRight
        }

        currentScale = min(1.0 + amplitude * Float(os.boost), 2.5)

        let intensity = bins.amplitude(for: settings.channelMode, binRange: 0..<4)
        currentInnerColor = lerpColor(from: os.innerColorLow, to: os.innerColorHigh, t: intensity)
        currentOuterColor = lerpColor(from: os.outerColorLow, to: os.outerColorHigh, t: intensity,
                                      alphaOverride: Float(os.outerOpacity))
    }

    private func reset() {
        smoothedLeft  = 0
        smoothedRight = 0
        currentScale  = 1.0
    }

    // MARK: - Vertex Building

    private func buildOrbData() -> TrailData {
        let os = orbSettings
        let cx = Float(sceneSize.width  * settings.positionX)
        let cy = Float(sceneSize.height * settings.positionY)
        let center = SIMD2<Float>(cx, cy)

        let innerR = Float(os.baseRadius) * currentScale
        let outerR = innerR * Float(os.outerRadiusMultiplier)

        var vertices: [TrailVertex] = []
        vertices.reserveCapacity(fanSegments * 3 * 2)

        // Outer glow first (drawn underneath inner orb)
        appendFan(to: &vertices, center: center, radius: outerR,
                  color: currentOuterColor, alpha: opacity)

        // Inner orb on top
        appendFan(to: &vertices, center: center, radius: innerR,
                  color: currentInnerColor, alpha: opacity)

        return TrailData(vertices: vertices, primitiveType: .triangle)
    }

    private func appendFan(to vertices: inout [TrailVertex],
                            center: SIMD2<Float>, radius: Float,
                            color: SIMD4<Float>, alpha: Float) {
        let step = Float.pi * 2 / Float(fanSegments)
        let centerVert = TrailVertex(position: center, color: color, alpha: alpha, edgeDist: 0)

        for i in 0..<fanSegments {
            let a0 = step * Float(i)
            let a1 = step * Float(i + 1)
            let p0 = SIMD2<Float>(center.x + cos(a0) * radius, center.y + sin(a0) * radius)
            let p1 = SIMD2<Float>(center.x + cos(a1) * radius, center.y + sin(a1) * radius)
            vertices.append(centerVert)
            vertices.append(TrailVertex(position: p0, color: color, alpha: alpha, edgeDist: 1))
            vertices.append(TrailVertex(position: p1, color: color, alpha: alpha, edgeDist: 1))
        }
    }

    // MARK: - Color Helpers

    private func lerpColor(from lo: ColorData, to hi: ColorData,
                            t: Float, alphaOverride: Float? = nil) -> SIMD4<Float> {
        let r = Float(lo.red)   + (Float(hi.red)   - Float(lo.red))   * t
        let g = Float(lo.green) + (Float(hi.green)  - Float(lo.green)) * t
        let b = Float(lo.blue)  + (Float(hi.blue)   - Float(lo.blue))  * t
        let a = alphaOverride ?? (Float(lo.alpha) + (Float(hi.alpha) - Float(lo.alpha)) * t)
        return SIMD4(r, g, b, a)
    }
}
