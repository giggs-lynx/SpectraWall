//
//  OrbEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import AppKit
import simd
import Combine
import OSLog

class OrbEffect: NSObject {

    // MARK: - Properties

    private var sceneSize: CGSize
    private var settings: LayerSettings
    private var cancellables = Set<AnyCancellable>()

    private var smoothedLeft:  Float = 0
    private var smoothedRight: Float = 0

    // Derived from audio each callback; read in tick (both on main thread)
    private var currentScale:      Float = 0
    private var currentInnerColor: SIMD4<Float> = SIMD4(0.2, 0.4, 1.0, 1.0)
    private var currentOuterColor: SIMD4<Float> = SIMD4(0.2, 0.4, 1.0, 0.15)

    // Lerped display values — inner 50ms, outer 80ms (matches SKAction durations)
    private var renderedInnerScale: Float = 0
    private var renderedOuterScale: Float = 0
    private var lastTickTime: TimeInterval = 0

    // Cached on the renderQueue via Combine subscription so tick never touches
    // AppSettings (a SwiftUI-observed ObservableObject) from a background thread.
    private var cachedMotionStyle: MotionStyle = .snappy

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

    // DEBUG: per-orb L/R sync diagnostic. Logs the channelMode + currentScale at
    // throttled rate so we can compare two orbs ingesting the same audio event.
    private static let orbDiagLog = Logger(subsystem: "com.spectrawall.app", category: "OrbDiag")
    private static let orbTickDiagLog = Logger(subsystem: "com.spectrawall.app", category: "OrbTickDiag")
    private static let orbLagDiagLog = Logger(subsystem: "com.spectrawall.app", category: "OrbLagDiag")
    private var orbDiagCount: Int = 0
    private var orbDiagFirstTime: TimeInterval = 0
    private var orbTickDiagCount: Int = 0
    private var lastAudioBinsTime: TimeInterval = 0
    private var maxGapInWindow: TimeInterval = 0
    private var maxLatencyInWindow: TimeInterval = 0
    private var audioEventCountInWindow: Int = 0
    private var windowStartTime: TimeInterval = 0
    /// Total events this sink has processed. AudioDataBus.sourceEventCount minus
    /// this = backlog size at the moment the sink reads it. If it grows over time
    /// → renderQueue can't keep up with source rate (THE accumulation pattern).
    private var mySinkEventCount: UInt64 = 0
    private var maxBacklogInWindow: UInt64 = 0

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
        // Same queue as renderer's tick — no locks, no main-thread dependency.
        let queue: DispatchQueue = renderer?.renderQueue ?? .main
        AudioDataBus.shared.spectrumPublisher
            .receive(on: queue)
            .sink { [weak self] bins in self?.onAudioBins(bins) }
            .store(in: &cancellables)

        AudioDataBus.shared.resetPublisher
            .receive(on: queue)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellables)

        // Cache motionStyle locally so tick doesn't access AppSettings (an
        // ObservableObject) from this background queue every frame. Initial value
        // is read once here on main during init (safe), then updated via sink.
        cachedMotionStyle = AppSettings.shared.motionStyle
        AppSettings.shared.$motionStyle
            .receive(on: queue)
            .sink { [weak self] style in self?.cachedMotionStyle = style }
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

        // TEMP: revert to single exponential lerp (no motionStyle switch). If lag
        // accumulation disappears with this, the snappy path was the culprit.
        let dt = lastTickTime == 0 ? 0.016 : min(timestamp - lastTickTime, 0.1)
        renderedInnerScale += (currentScale - renderedInnerScale) * Float(1.0 - exp(-dt / 0.05))
        renderedOuterScale += (currentScale - renderedOuterScale) * Float(1.0 - exp(-dt / 0.08))
        lastTickTime = timestamp

        renderer.updateOrb(id: id, data: buildOrbData())
    }

    // MARK: - Audio

    private func onAudioBins(_ bins: StereoBins) {
        let os = orbSettings

        // DEBUG: track inter-arrival of audio sink invocations to detect renderQueue
        // backlog. If audio is emitted at ~100Hz, gap should be ~10ms. If gap grows,
        // sink is being delivered late (queue saturated).
        let nowMark = CACurrentMediaTime()
        if windowStartTime == 0 { windowStartTime = nowMark }
        if lastAudioBinsTime > 0 {
            let gap = nowMark - lastAudioBinsTime
            if gap > maxGapInWindow { maxGapInWindow = gap }
        }
        lastAudioBinsTime = nowMark
        audioEventCountInWindow += 1
        // True source-to-sink latency: source updated lastSourceEmitTime BEFORE
        // emitting; if our sink processes events real-time, lag is the small
        // queue-dispatch delay (~ms). If sink is N seconds behind, lag grows
        // because source has advanced N seconds while we processed older events.
        let srcEmit = AudioDataBus.shared.lastSourceEmitTime
        let latency = srcEmit > 0 ? nowMark - srcEmit : 0
        if abs(latency) > self.maxLatencyInWindow { self.maxLatencyInWindow = abs(latency) }
        // Backlog measure: source has emitted N events, sink has processed M.
        // (N - M - 1) = events queued ahead of THIS sink invocation. Grows = backlog.
        mySinkEventCount &+= 1
        let backlog = AudioDataBus.shared.sourceEventCount &- mySinkEventCount
        if backlog > maxBacklogInWindow { maxBacklogInWindow = backlog }
        if nowMark - windowStartTime >= 2.0 {
            let elapsed = nowMark - windowStartTime
            let rate = Double(audioEventCountInWindow) / elapsed
            let gapMs = Int(self.maxGapInWindow * 1000)
            let latMs = Int(self.maxLatencyInWindow * 1000)
            let n = self.audioEventCountInWindow
            let bk = self.maxBacklogInWindow
            Self.orbLagDiagLog.info("""
                rate=\(rate, privacy: .public)Hz \
                maxGap=\(gapMs, privacy: .public)ms \
                maxLatency=\(latMs, privacy: .public)ms \
                maxBacklog=\(bk, privacy: .public) \
                n=\(n, privacy: .public)
                """)
            windowStartTime = nowMark
            audioEventCountInWindow = 0
            maxGapInWindow = 0
            maxLatencyInWindow = 0
            maxBacklogInWindow = 0
        }

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

        // Silence gate uses peak across the FULL spectrum (not just bins 0..<8 which
        // is what leftAmplitude/rightAmplitude default to). Otherwise music with no
        // bass content (vocals, hi-hat passages, high synths) reads as silent and the
        // orb disappears mid-song. Also peak-based + combined L/R so both orbs go
        // silent together instead of one diverging when smoothing fluctuates near
        // the threshold.
        let peakAmp = max(bins.left.max() ?? 0, bins.right.max() ?? 0)
        let silenceLo: Float = 0.001
        let silenceHi: Float = 0.01
        let t = (peakAmp - silenceLo) / (silenceHi - silenceLo)
        let clampedT = max(0, min(1, t))
        let silenceGate = clampedT * clampedT * (3 - 2 * clampedT)
        currentScale = silenceGate * min(1.0 + amplitude * Float(os.boost), 2.5)

        // DEBUG: heartbeat per-orb. Throttle to every 30 events (~300ms @ 100Hz)
        // so the log lines from left orb and right orb interleave cleanly for
        // post-hoc comparison via `log show ... category == "OrbDiag"`.
        orbDiagCount += 1
        if orbDiagCount % 90 == 0 {
            let now = CACurrentMediaTime()
            if orbDiagFirstTime == 0 { orbDiagFirstTime = now }
            let elapsed = now - orbDiagFirstTime
            let modeStr: String
            switch settings.channelMode {
            case .stereo: modeStr = "stereo"
            case .mono:   modeStr = "mono"
            case .left:   modeStr = "left"
            case .right:  modeStr = "right"
            }
            let scale = self.currentScale
            Self.orbDiagLog.info("""
                t=\(elapsed, privacy: .public)s mode=\(modeStr, privacy: .public) \
                amp=\(amplitude, privacy: .public) scale=\(scale, privacy: .public) \
                L=\(leftAmp, privacy: .public) R=\(rightAmp, privacy: .public)
                """)
        }

        let intensity = bins.amplitude(for: settings.channelMode, binRange: 0..<4)
        currentInnerColor = lerpColor(from: os.innerColorLow, to: os.innerColorHigh, t: intensity)
        currentOuterColor = lerpColor(from: os.outerColorLow, to: os.outerColorHigh, t: intensity,
                                      alphaOverride: Float(os.outerOpacity))
    }

    private func reset() {
        smoothedLeft       = 0
        smoothedRight      = 0
        currentScale       = 0
        renderedInnerScale = 0
        renderedOuterScale = 0
        lastTickTime       = 0
    }

    // MARK: - Vertex Building

    private func buildOrbData() -> TrailData {
        let os = orbSettings
        let cx = Float(sceneSize.width  * settings.positionX)
        let cy = Float(sceneSize.height * settings.positionY)
        let center = SIMD2<Float>(cx, cy)

        let innerR = Float(os.baseRadius) * renderedInnerScale
        let outerR = Float(os.baseRadius) * renderedOuterScale * Float(os.outerRadiusMultiplier)

        var vertices: [TrailVertex] = []
        vertices.reserveCapacity(fanSegments * 3 * 2)

        // Outer glow first (drawn underneath inner orb); negative edgeDist = glow mode in shader
        appendFan(to: &vertices, center: center, radius: outerR,
                  color: currentOuterColor, alpha: opacity, outerEdgeDist: -1)

        // Inner solid disk on top; positive edgeDist = solid-disk mode in shader
        appendFan(to: &vertices, center: center, radius: innerR,
                  color: currentInnerColor, alpha: opacity, outerEdgeDist: +1)

        return TrailData(vertices: vertices, primitiveType: .triangle)
    }

    private func appendFan(to vertices: inout [TrailVertex],
                            center: SIMD2<Float>, radius: Float,
                            color: SIMD4<Float>, alpha: Float,
                            outerEdgeDist: Float) {
        let step = Float.pi * 2 / Float(fanSegments)
        let centerVert = TrailVertex(position: center, color: color, alpha: alpha, edgeDist: 0)

        for i in 0..<fanSegments {
            let a0 = step * Float(i)
            let a1 = step * Float(i + 1)
            let p0 = SIMD2<Float>(center.x + cos(a0) * radius, center.y + sin(a0) * radius)
            let p1 = SIMD2<Float>(center.x + cos(a1) * radius, center.y + sin(a1) * radius)
            vertices.append(centerVert)
            vertices.append(TrailVertex(position: p0, color: color, alpha: alpha, edgeDist: outerEdgeDist))
            vertices.append(TrailVertex(position: p1, color: color, alpha: alpha, edgeDist: outerEdgeDist))
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
