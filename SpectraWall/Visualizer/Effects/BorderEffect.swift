//
//  BorderEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import AppKit
import QuartzCore

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
    let echoDecaySpeed: CGFloat  = 1.5
    let echoMaxScale: CGFloat    = 5.0
    let echoStartAlpha: CGFloat  = 0.25
    let echoLayerCount: Int      = 3
    let echoLayerDelay: CGFloat  = 3.0
    let maxScaleGhosts: Int      = 20

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

    override func removeFromRenderer() {
        renderer?.removeTrail(id: id)
    }

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
                renderer?.removeTrail(id: id)
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

    override func onReset() {
        smoothedLeft       = 0
        smoothedRight      = 0
        lastAmplitudeLeft  = 0
        lastAmplitudeRight = 0
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
        guard scaleGhosts.count < maxScaleGhosts else { return }

        let now = lastUpdateTime
        guard now - lastEchoTime > minEchoInterval else { return }

        let bs = borderSettings
        let sensitivity: Float = 1.1

        if strokes.count == 1 {
            let combined = (smoothedLeft + smoothedRight) / 2
            let lastCombined = (lastAmplitudeLeft + lastAmplitudeRight) / 2
            if combined > Float(bs.pulseThreshold) && combined > lastCombined * sensitivity {
                spawnScalePulse(strokeIndex: 0, amplitude: combined)
                lastEchoTime = now
            }
        } else {
            if smoothedLeft > Float(bs.pulseThreshold) && smoothedLeft > lastAmplitudeLeft * sensitivity {
                spawnScalePulse(strokeIndex: 0, amplitude: smoothedLeft)
                lastEchoTime = now
            }
            if smoothedRight > Float(bs.pulseThreshold) && smoothedRight > lastAmplitudeRight * sensitivity {
                spawnScalePulse(strokeIndex: 1, amplitude: smoothedRight)
                lastEchoTime = now
            }
        }
    }

    // MARK: - Spawn Scale Pulse

    private func spawnScalePulse(strokeIndex: Int, amplitude: Float) {
        for layerIndex in 0..<echoLayerCount {
            scaleGhosts.append(ScaleGhost(
                lifetime: -0.05,
                delay: CGFloat(layerIndex) * echoLayerDelay,
                progressOffset: 0.0,
                strokeIndex: strokeIndex,
                amplitude: amplitude
            ))
        }
    }

    // MARK: - Scale Ghost Update

    private func updateScaleGhosts(deltaTime: TimeInterval) -> [TrailVertex] {
        let dt = CGFloat(deltaTime)
        var ghostVertices: [TrailVertex] = []

        for index in (0..<scaleGhosts.count).reversed() {
            if scaleGhosts[index].delay > 0 {
                scaleGhosts[index].delay -= dt
                continue
            }

            scaleGhosts[index].lifetime += dt * echoDecaySpeed
            let lifetime = scaleGhosts[index].lifetime

            if lifetime >= 1.0 {
                scaleGhosts.remove(at: index)
                continue
            }

            guard lifetime >= 0 else { continue }

            let easedT = 1.0 - pow(max(0, 1.0 - lifetime), 4)
            let scale  = 1.0 + easedT * (echoMaxScale - 1.0)
            let alpha  = Float(echoStartAlpha * max(0, 1.0 - pow(lifetime, 1.2))) * opacity

            let ghost = scaleGhosts[index]
            let data = buildGhostTrailData(
                strokeIndex: ghost.strokeIndex,
                progressOffset: ghost.progressOffset,
                amplitude: ghost.amplitude,
                scale: CGFloat(scale),
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

        let deltaTime     = currentTime - lastUpdateTime
        lastUpdateTime    = currentTime

        let bs            = borderSettings
        let deltaProgress = bs.speed * deltaTime * (bs.clockwise ? 1 : -1)

        for strokeIndex in 0..<strokes.count {
            var progress = (strokes[strokeIndex].progress + deltaProgress)
                .truncatingRemainder(dividingBy: 1.0)
            if progress < 0 { progress += 1.0 }
            strokes[strokeIndex].progress = progress
        }

        guard let renderer else { return }

        var allVertices: [TrailVertex] = []
        allVertices.reserveCapacity(300 * strokes.count + 300 * scaleGhosts.count)

        for strokeIndex in 0..<strokes.count {
            let data = buildTrailData(strokeIndex: strokeIndex)
            if !allVertices.isEmpty,
               let last = allVertices.last,
               let first = data.vertices.first {
                allVertices.append(last)
                allVertices.append(last)
                allVertices.append(first)
            }
            allVertices.append(contentsOf: data.vertices)
        }

        let ghostVerts = updateScaleGhosts(deltaTime: deltaTime)
        if !ghostVerts.isEmpty {
            if let last = allVertices.last, let first = ghostVerts.first {
                allVertices.append(last)
                allVertices.append(last)
                allVertices.append(first)
            }
            allVertices.append(contentsOf: ghostVerts)
        }

        if fadeAlpha < 1.0 {
            for i in 0..<allVertices.count {
                allVertices[i].alpha *= fadeAlpha
            }
        }

        renderer.updateTrail(id: id, data: TrailData(vertices: allVertices))
    }
}
