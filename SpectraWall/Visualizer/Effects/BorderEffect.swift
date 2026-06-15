//
//  BorderEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import AppKit
import QuartzCore
import SwiftUI

class BorderEffect: BaseEffect {

    // MARK: - Settings access

    var borderSettings: BorderSettings {
        layer.effectSettings as? BorderSettings ?? .defaults
    }

    // MARK: - Stroke state

    struct StrokeState {
        var progress: Double = 0.0
    }

    var strokes: [StrokeState] = []
    var smoothedLeft: Float = 0
    var smoothedRight: Float = 0
    var lastAmplitudeLeft: Float = 0
    var lastAmplitudeRight: Float = 0
    // Width breathing rides its own loudness envelope (the shared pulse
    // envelope is too smooth — measured norm pinned at exactly 1.0, it never
    // moves). breathEnv rises fast, falls with ~0.5s half-life; breathAgc is
    // its running peak so the swing is normalized to the source's own level.
    // Note the timescale: during continuous music norm sits at 0.84–1.0, so
    // breathing tracks multi-second loud/quiet passages, not individual beats
    // — a deliberate trade against a beat-driven pop.
    private var breathEnv: Float = 0
    private var breathAgc: Float = 0.05

    private var lastUpdateTime: TimeInterval = 0
    var perimeterLength: CGFloat = 0

    // MARK: - Fade-out tracking

    /// Silence fade-out: tracks when raw audio went below threshold.
    /// After a short grace period the trail fades to 0 over fadeDuration; any audio
    /// clearly above the resume threshold clears silentSince and the trail snaps back.
    /// Hysteresis: enter silence at the low threshold, exit only above the high one —
    /// prevents system audio noise floor jitter from continually resetting the timer.
    private var silentSince: TimeInterval?
    private let silenceEnterThreshold: Float = 0.02
    private let silenceExitThreshold: Float  = 0.1
    private let silenceGrace: TimeInterval = 0.2
    private let silenceFadeDuration: TimeInterval = 0.8

    private var trailHidden = false

    // MARK: - Scale Pulse Echo

    struct ScaleGhost {
        var lifetime: CGFloat
        var delay: CGFloat
        var progressOffset: Double
        var strokeIndex: Int
        var amplitude: Float
    }

    var scaleGhosts: [ScaleGhost] = []

    let echoThreshold: Float     = 0.08
    // Width/length deltas at ghostSize=1. Final peak scale at runtime:
    //   widthScale  = 1 + borderSettings.ghostSize × echoWidthDelta
    //   lengthScale = 1 + borderSettings.ghostSize × echoLengthDelta
    // Width/length ratio (1.1 : 0.05 = 22:1) stays constant across ghostSize,
    // so the silhouette grows the same shape no matter how big the user
    // slides Ghost Size.
    let echoWidthDelta: CGFloat   = 1.1      // ghostSize=1 → width  × 2.1
    let echoLengthDelta: CGFloat  = 0.05     // ghostSize=1 → length × 1.05
    // ghost fill alpha at lifetime=0 comes from borderSettings.ghostOpacity
    // ghost decay speed comes from borderSettings.ghostDecay (lifetime ≈ 1/decay)
    let echoAlphaCurve: CGFloat  = 2.5     // alpha decays as (1 - t^curve);
                                           // higher = stays visible longer
                                           // before snapping out at the end.
    let maxScaleGhosts: Int      = 20

    // Per-stroke flash that runs on the main trail at the instant a pulse
    // spawns its ghost — a quick "energy burst" feel before the ghost takes
    // over. Decays exponentially with ~120ms half-life; while flashing the
    // stroke's colour is lerped toward white and its alpha boosted.
    var strokeFlashIntensity: [Float] = []
    let flashHalfLife: TimeInterval = 0.12
    // Mix-toward-white and alpha boost at flash peak come from
    // borderSettings.pulseFlash; alpha boost is derived from the mix value so
    // brightness and visibility move together.

    // MARK: - Segment cache

    var segmentCache: [BorderSegment]?
    var cachedSceneSize: CGSize = .zero
    var cachedCornerRadius: Double = -1
    let trailSegments = 20

    // MARK: - Settings-change tracking

    private var lastStrokeCount: Int = 0
    private var lastCornerRadius: Double = 0
    private var lastBaseWidth: Double = 0

    private var lastEchoTime: TimeInterval = 0
    private let minEchoInterval: TimeInterval = 0.12

    override class var effectTypeName: String { "Border" }

    // MARK: - Initialization

    override init(size: CGSize, layer: LayerSettings, screen: NSScreen) {
        let bs = (layer.effectSettings as? BorderSettings) ?? .defaults
        self.lastStrokeCount  = bs.strokeCount
        self.lastCornerRadius = bs.cornerRadius
        self.lastBaseWidth    = bs.baseWidth
        // Start in silent state so the trail is invisible until audio arrives,
        // rather than animating around the screen on launch with no audio yet.
        self.silentSince = CACurrentMediaTime() - 0.2 - 0.8
        super.init(size: size, layer: layer, screen: screen)
        setupStrokes()
    }

    // MARK: - BaseEffect hooks

    override func onLayerSettingsChanged() {
        let bs = borderSettings
        if bs.strokeCount  != lastStrokeCount  ||
           bs.cornerRadius != lastCornerRadius ||
           bs.baseWidth    != lastBaseWidth {
            lastStrokeCount  = bs.strokeCount
            lastCornerRadius = bs.cornerRadius
            lastBaseWidth    = bs.baseWidth
            setupStrokes()
        } else {
            updateVisuals()
        }
    }

    override func onTick(_ timestamp: TimeInterval) {
        // Smooth fade-out when audio has been silent past the grace period.
        // Fade applies uniformly to main trail + ghosts; once fully faded, drop
        // queued ghosts (some are still in their pre-render delay) and reset the
        // dt anchor so the next resumed frame doesn't see a huge deltaTime.
        let fade = currentFadeAlpha()
        if fade <= 0 {
            if !trailHidden {
                renderer?.remove(id: id)
                scaleGhosts.removeAll()
                lastUpdateTime = 0
                trailHidden = true
            }
            return
        }
        trailHidden = false

        update(timestamp, fadeAlpha: fade)
    }

    override func onAudio(_ bins: StereoBins) {
        updateAmplitude(bins: bins)
    }

    // `override` must live in the class body (Swift forbids it in extensions);
    // the geometry build lives in BorderEffectDebug.swift.
    override func drawDebug(into canvas: inout DebugCanvas) {
        buildBorderDebug(into: &canvas)
    }

    override func onReset() {
        smoothedLeft       = 0
        smoothedRight      = 0
        lastAmplitudeLeft  = 0
        lastAmplitudeRight = 0
        breathEnv          = 0
        breathAgc          = 0.05
        scaleGhosts        = []
    }

    // MARK: - Audio

    private func updateAmplitude(bins: StereoBins) {
        let bs = borderSettings
        let leftAmp  = bins.leftAmplitude()
        let rightAmp = bins.rightAmplitude()

        let leftCoeff  = leftAmp  > smoothedLeft  ? Float(bs.pulseAttack) : Float(bs.pulseRelease)
        let rightCoeff = rightAmp > smoothedRight ? Float(bs.pulseAttack) : Float(bs.pulseRelease)

        smoothedLeft  = smoothedLeft  * (1 - leftCoeff)  + leftAmp  * leftCoeff
        smoothedRight = smoothedRight * (1 - rightCoeff) + rightAmp * rightCoeff
        let rawCombined = (leftAmp + rightAmp) / 2
        breathEnv = rawCombined > breathEnv
            ? breathEnv * 0.7 + rawCombined * 0.3
            : breathEnv * 0.985
        breathAgc = max(0.02, max(breathEnv, breathAgc * 0.997))

        // Silence detection uses peak across the FULL spectrum, not just bins 0..<8
        // (which leftAmp/rightAmp use). High-frequency-only musical passages have
        // zero bass and would falsely register as silent → trail fades mid-song.
        // Hysteresis: enter at the low threshold, exit only above the higher one
        // so noise-floor jitter between the two doesn't keep resetting the fade timer.
        let peakAmp = max(bins.left.max() ?? 0, bins.right.max() ?? 0)
        if peakAmp < silenceEnterThreshold {
            if silentSince == nil { silentSince = CACurrentMediaTime() }
        } else if peakAmp > silenceExitThreshold {
            silentSince = nil
        }

        detectAndSpawnEcho()

        lastAmplitudeLeft  = smoothedLeft
        lastAmplitudeRight = smoothedRight
    }

    /// Returns the trail's current fade-out alpha multiplier.
    /// 1.0 while audio is present or within the grace window; ramps to 0 over
    /// silenceFadeDuration after grace; snaps back to 1.0 the moment audio returns.
    private func currentFadeAlpha() -> Float {
        guard let since = silentSince else { return 1.0 }
        let elapsed = CACurrentMediaTime() - since
        if elapsed < silenceGrace { return 1.0 }
        let t = (elapsed - silenceGrace) / silenceFadeDuration
        if t >= 1 { return 0 }
        return Float(1 - t)
    }

    private func detectAndSpawnEcho() {
        let now = lastUpdateTime
        guard now - lastEchoTime > minEchoInterval else { return }

        let bs = borderSettings
        let sensitivity: Float = 1.1

        // Detect a beat from the *combined* amplitude regardless of stroke
        // count — both strokes belong to the same effect so they should pulse
        // on the same beat. Per-channel detection (previous behaviour) made
        // L/R cross threshold on different frames, so the two strokes pulsed
        // visibly out of sync. Each stroke still spawns with its own channel's
        // amplitude so left/right loudness still drives ghost intensity.
        let combined = (smoothedLeft + smoothedRight) / 2
        let lastCombined = (lastAmplitudeLeft + lastAmplitudeRight) / 2
        guard combined > Float(bs.pulseThreshold),
              combined > lastCombined * sensitivity else {
            return
        }

        guard scaleGhosts.count < maxScaleGhosts else { return }

        if strokes.count == 1 {
            spawnScalePulse(strokeIndex: 0, amplitude: combined)
        } else {
            spawnScalePulse(strokeIndex: 0, amplitude: smoothedLeft)
            spawnScalePulse(strokeIndex: 1, amplitude: smoothedRight)
        }
        lastEchoTime = now
    }

    // MARK: - Spawn Scale Pulse

    private func spawnScalePulse(strokeIndex: Int, amplitude: Float) {
        // Light up the corresponding stroke on the main trail; decayed each
        // frame in update().
        if strokeIndex < strokeFlashIntensity.count {
            strokeFlashIntensity[strokeIndex] = 1.0
        }
        // Ghost is optional; flash on the main trail above still fires either
        // way.
        guard borderSettings.ghostEnabled else { return }
        // One ghost per pulse — earlier versions spawned three echoes spaced
        // by `echoLayerDelay`, but with a 1-second ghost lifetime they never
        // overlapped visually and read as three isolated pulses instead of a
        // single burst.
        scaleGhosts.append(ScaleGhost(
            lifetime: -0.05,
            delay: 0,
            progressOffset: 0.0,
            strokeIndex: strokeIndex,
            amplitude: amplitude
        ))
    }

    // MARK: - Scale Ghost Update

    private func updateScaleGhosts(deltaTime: TimeInterval) -> [EffectVertex] {
        let dt = CGFloat(deltaTime)
        var ghostVertices: [EffectVertex] = []

        for index in (0..<scaleGhosts.count).reversed() {
            if scaleGhosts[index].delay > 0 {
                scaleGhosts[index].delay -= dt
                continue
            }

            scaleGhosts[index].lifetime += dt * CGFloat(borderSettings.ghostDecay)
            let lifetime = scaleGhosts[index].lifetime

            if lifetime >= 1.0 {
                scaleGhosts.remove(at: index)
                continue
            }

            guard lifetime >= 0 else { continue }

            let easedT = 1.0 - pow(max(0, 1.0 - lifetime), 4)
            let ghostSize = CGFloat(borderSettings.ghostSize)
            let widthScale  = 1.0 + easedT * ghostSize * echoWidthDelta
            let lengthScale = 1.0 + easedT * ghostSize * echoLengthDelta
            let ghostOpacity = CGFloat(borderSettings.ghostOpacity)
            let alpha  = Float(ghostOpacity * max(0, 1.0 - pow(lifetime, echoAlphaCurve))) * opacity

            let ghost = scaleGhosts[index]
            let data = buildScaledGhostMesh(
                strokeIndex: ghost.strokeIndex,
                amplitude: ghost.amplitude,
                widthScale: CGFloat(widthScale),
                lengthScale: CGFloat(lengthScale),
                alpha: alpha
            )

            if !ghostVertices.isEmpty,
               let last = ghostVertices.last,
               let first = data.vertices.first {
                ghostVertices.append(last)
                ghostVertices.append(last)
                ghostVertices.append(first)
            }
            ghostVertices.append(contentsOf: data.vertices)
        }

        return ghostVertices
    }

    // MARK: - Setup & Visual Updates

    private func setupStrokes() {
        segmentCache = nil
        scaleGhosts  = []
        strokes      = []

        let count = borderSettings.strokeCount
        for strokeIndex in 0..<count {
            var state = StrokeState()
            state.progress = count == 2 ? Double(strokeIndex) * 0.5 : 0.0
            strokes.append(state)
        }
        strokeFlashIntensity = Array(repeating: 0, count: count)

        updatePerimeterLength()
        updateVisuals()
    }

    private func updateVisuals() {
        updatePerimeterLength()
    }

    private func updatePerimeterLength() {
        // Sum segment lengths instead of using the closed-form `2 line + 2πR` formula —
        // the corner segments are now Bézier curves with no analytic arc length, only the
        // LUT total. borderSegments() is cached on (sceneSize, cornerRadius) so this is free.
        perimeterLength = borderSegments().reduce(into: CGFloat(0)) { $0 += $1.length }
    }

    // MARK: - Main Update Loop

    func update(_ currentTime: TimeInterval, fadeAlpha: Float = 1.0) {
        guard lastUpdateTime > 0 else {
            lastUpdateTime = currentTime
            return
        }

        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        let flashDecay = Float(exp(-deltaTime / flashHalfLife))
        for i in 0..<strokeFlashIntensity.count {
            strokeFlashIntensity[i] *= flashDecay
        }

        let bs = borderSettings
        // Beat surge rides the flash envelope (spikes to 1 on beat, ~120ms
        // half-life) so the trail lurches forward and settles back.
        let flashEnv = Double(strokeFlashIntensity.max() ?? 0)
        let deltaProgress = bs.speed * (1 + bs.pulseSpeedBoost * flashEnv)
            * deltaTime * (bs.clockwise ? 1 : -1)

        for strokeIndex in 0..<strokes.count {
            var progress = (strokes[strokeIndex].progress + deltaProgress)
                .truncatingRemainder(dividingBy: 1.0)
            if progress < 0 { progress += 1.0 }
            strokes[strokeIndex].progress = progress
        }

        guard let renderer else { return }

        let allVertices = assembleFrameVertices(deltaTime: deltaTime, fadeAlpha: fadeAlpha)
        renderer.submit(id: id, type: .border, mesh: EffectMesh(vertices: allVertices))
    }

    private func assembleFrameVertices(deltaTime: TimeInterval, fadeAlpha: Float) -> [EffectVertex] {
        var allVertices: [EffectVertex] = []
        allVertices.reserveCapacity(300 * strokes.count + 300 * scaleGhosts.count)

        for strokeIndex in 0..<strokes.count {
            let data = buildEffectMesh(strokeIndex: strokeIndex)
            appendWithDegenerateJoin(&allVertices, new: data.vertices)
        }

        let ghostVerts = updateScaleGhosts(deltaTime: deltaTime)
        appendWithDegenerateJoin(&allVertices, new: ghostVerts)

        if fadeAlpha < 1.0 {
            for i in 0..<allVertices.count {
                allVertices[i].alpha *= fadeAlpha
            }
        }
        return allVertices
    }

    /// Width multiplier for the breathing option: rides the dedicated breath
    /// envelope (see breathEnv), not the flash spike, so the trail swells and
    /// shrinks with the rhythm instead of twitching per beat. AGC-normalized
    /// and centred on baseWidth (1 ± breath/2) so both the swell and the
    /// shrink half of the breath are visible.
    var widthBreathMultiplier: CGFloat {
        let breath = borderSettings.widthBreath
        guard breath > 0 else { return 1 }
        // Asymmetric swing: quiet floor at 1 − breath/2, loud peak at
        // 1 + 1.5·breath (0.5×…2.5× at full slider). The symmetric ±breath/2
        // version capped at 1.5× and read as "barely moving" even maxed out.
        let normalized = min(breathEnv / breathAgc, 1)
        return 1 - CGFloat(breath) * 0.5 + CGFloat(breath) * 2 * CGFloat(normalized)
    }

    private func appendWithDegenerateJoin(_ vertices: inout [EffectVertex], new: [EffectVertex]) {
        guard !new.isEmpty else { return }
        if let last = vertices.last, let first = new.first {
            vertices.append(last)
            vertices.append(last)
            vertices.append(first)
        }
        vertices.append(contentsOf: new)
    }
}

// MARK: - EffectDescriptor

extension BorderEffect {
    static let descriptor = EffectDescriptor(
        type: .border,
        displayName: "Border",
        iconAssetName: "border",
        renderOrder: 0,
        commonSettings: [.opacity, .channelMode],   // border path follows screen edge; position has no meaning
        makeDefaultSettings: { BorderSettings.defaults },
        settingsCodec: .make(BorderSettings.self),
        makeEffect: { size, layer, screen in
            BorderEffect(size: size, layer: layer, screen: screen)
        },
        makeSettingsView: { AnyView(BorderSettingsSection(layer: $0)) },
        pipelineSpec: PipelineSpec(
            vertexFunctionName: "border_vertex",
            fragmentFunctionName: "border_fragment",
            blendMode: .lighten
        )
    )
}
