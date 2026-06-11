//
//  OrbEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import AppKit
import SwiftUI
import simd
import Combine

class OrbEffect: BaseEffect {

    // MARK: - Properties

    private var smoothedLeft: Float = 0
    private var smoothedRight: Float = 0

    // Derived from audio each callback; read in onTick (same renderQueue).
    private var currentScale: Float = 0
    private var currentInnerColor: SIMD4<Float> = SIMD4(0.2, 0.4, 1.0, 1.0)
    private var currentOuterColor: SIMD4<Float> = SIMD4(0.2, 0.4, 1.0, 0.15)

    // Lerped display values — inner 50ms, outer 80ms (matches SKAction durations)
    private var renderedInnerScale: Float = 0
    private var renderedOuterScale: Float = 0
    private var lastTickTime: TimeInterval = 0

    // Beat-spawned ripple rings: birth timestamps, capped at maxRipples.
    // Detection mirrors BorderEffect's pulse latch: combined amplitude crosses
    // the threshold rising-edge, re-arms once it falls back below half.
    private var ripples: [TimeInterval] = []
    private var pendingRipple = false
    private var isPulsing = false
    private let rippleThreshold: Float = 0.01
    private let maxRipples = 6
    private let rippleHalfThickness: Float = 4

    // Animation style cached on renderQueue via Combine sink so onTick never
    // touches AppSettings (an ObservableObject) from a background thread.
    // Wired in init() right after super.init so `renderer` / renderQueue exist.
    private var cachedMotionStyle: MotionStyle = .smooth

    private var orbSettings: OrbSettings {
        layer.effectSettings as? OrbSettings ?? .defaults
    }

    let fanSegments = 32

    override class var effectTypeName: String { "Orb" }

    // MARK: - Lifecycle

    override init(size: CGSize, layer: LayerSettings, screen: NSScreen) {
        super.init(size: size, layer: layer, screen: screen)
        cachedMotionStyle = AppSettings.shared.motionStyle
        let queue: DispatchQueue = renderer?.renderQueue ?? .main
        AppSettings.shared.$motionStyle
            .receive(on: queue)
            .sink { [weak self] style in self?.cachedMotionStyle = style }
            .store(in: &cancellables)
    }

    // MARK: - BaseEffect hooks

    override func onReset() {
        smoothedLeft       = 0
        smoothedRight      = 0
        currentScale       = 0
        renderedInnerScale = 0
        renderedOuterScale = 0
        lastTickTime       = 0
        ripples.removeAll()
        pendingRipple      = false
        isPulsing          = false
    }

    override func onTick(_ timestamp: TimeInterval) {
        guard let renderer else { return }

        let dt = lastTickTime == 0 ? 0.016 : min(timestamp - lastTickTime, 0.1)
        switch cachedMotionStyle {
        case .snappy:
            // Linear tween rate: rendered closes the remaining distance over
            // a fixed duration, clamped so we never overshoot. Once the value
            // reaches the target it stops moving — sharp, no tail.
            let innerRate = Float(min(dt / 0.05, 1.0))
            let outerRate = Float(min(dt / 0.08, 1.0))
            renderedInnerScale += (currentScale - renderedInnerScale) * innerRate
            renderedOuterScale += (currentScale - renderedOuterScale) * outerRate
        case .smooth:
            // Exponential approach with longer time constants than snappy's
            // 50ms / 80ms so the tail is visibly distinct from the linear
            // reach. With matching time constants the two modes look almost
            // identical at 60Hz; bumping smooth to 180ms / 250ms makes the
            // dampened "trailing" feel obvious.
            renderedInnerScale += (currentScale - renderedInnerScale) * Float(1.0 - exp(-dt / 0.18))
            renderedOuterScale += (currentScale - renderedOuterScale) * Float(1.0 - exp(-dt / 0.25))
        }
        lastTickTime = timestamp

        if pendingRipple {
            pendingRipple = false
            if orbSettings.rippleEnabled {
                ripples.append(timestamp)
                if ripples.count > maxRipples {
                    ripples.removeFirst(ripples.count - maxRipples)
                }
            }
        }
        let decay = Float(orbSettings.rippleDecay)
        ripples.removeAll { Float(timestamp - $0) * decay >= 1 }

        renderer.submit(id: id, type: .orb, mesh: buildOrbData(at: timestamp))
    }

    // `override` must live in the class body (Swift forbids it in extensions);
    // the geometry build lives in OrbEffectDebug.swift.
    override func drawDebug(into canvas: inout DebugCanvas) {
        buildOrbDebug(into: &canvas)
    }

    override func onAudio(_ bins: StereoBins) {
        let os = orbSettings

        let leftAmp  = bins.leftAmplitude()
        let rightAmp = bins.rightAmplitude()
        let lCoeff   = leftAmp  > smoothedLeft  ? Float(os.attack) : Float(os.release)
        let rCoeff   = rightAmp > smoothedRight ? Float(os.attack) : Float(os.release)
        smoothedLeft  = smoothedLeft  * (1 - lCoeff) + leftAmp  * lCoeff
        smoothedRight = smoothedRight * (1 - rCoeff) + rightAmp * rCoeff

        let amplitude: Float
        switch layer.channelMode {
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
        let peakAmp = bins.peak
        let silenceLo = SilenceThreshold.enter
        let silenceHi = SilenceThreshold.exit
        let t = (peakAmp - silenceLo) / (silenceHi - silenceLo)
        let clampedT = max(0, min(1, t))
        let silenceGate = clampedT * clampedT * (3 - 2 * clampedT)
        currentScale = silenceGate * min(1.0 + amplitude * Float(os.boost), 2.5)

        // Ripple beat latch (combined so a beat spawns one ring, not per-channel).
        let combined = (smoothedLeft + smoothedRight) / 2
        if silenceGate > 0.5, combined > rippleThreshold, !isPulsing {
            isPulsing = true
            pendingRipple = true
        } else if combined < rippleThreshold * 0.5 {
            isPulsing = false
        }

        let intensity = bins.amplitude(for: layer.channelMode, binRange: 0..<4)
        currentInnerColor = lerpColor(from: os.innerColorLow, to: os.innerColorHigh, t: intensity)
        currentOuterColor = lerpColor(from: os.outerColorLow, to: os.outerColorHigh, t: intensity,
                                      alphaOverride: Float(os.outerOpacity))
    }

    // MARK: - Vertex Building

    /// Geometry shared by the render mesh and the debug wireframe in
    /// OrbEffectDebug.swift, so the skeleton can never drift from the mesh.
    struct OrbGeometry {
        let center: SIMD2<Float>
        let innerRadius: Float
        let outerRadius: Float
        let baseRadius: Float
    }

    func orbGeometry() -> OrbGeometry {
        let os = orbSettings
        let cx = Float(sceneSize.width  * layer.positionX)
        let cy = Float(sceneSize.height * layer.positionY)
        return OrbGeometry(
            center: SIMD2<Float>(cx, cy),
            innerRadius: Float(os.baseRadius) * renderedInnerScale,
            outerRadius: Float(os.baseRadius) * renderedOuterScale * Float(os.outerRadiusMultiplier),
            baseRadius: Float(os.baseRadius))
    }

    private func buildOrbData(at timestamp: TimeInterval) -> EffectMesh {
        let geo = orbGeometry()

        var vertices: [EffectVertex] = []
        vertices.reserveCapacity(fanSegments * 3 * 2 + ripples.count * fanSegments * 12)

        // Outer glow first (drawn underneath inner orb); negative edgeDist = glow mode in shader
        vertices.append(contentsOf: buildFan(center: geo.center, radius: geo.outerRadius,
                                             color: currentOuterColor, alpha: opacity,
                                             outerEdgeDist: -1))

        // Inner solid disk on top; positive edgeDist = solid-disk mode in shader
        vertices.append(contentsOf: buildFan(center: geo.center, radius: geo.innerRadius,
                                             color: currentInnerColor, alpha: opacity,
                                             outerEdgeDist: +1))

        appendRippleRings(at: timestamp, geo: geo, into: &vertices)

        return EffectMesh(vertices: vertices, primitiveType: .triangle)
    }

    /// Expanding annulus per live ripple. Three radial rows (edgeDist −1/0/−1)
    /// so the orb fragment's rim mask anti-aliases both band edges; the ring
    /// expands from the resting glow radius regardless of the audio-scaled
    /// outer radius so rings don't jitter with the music.
    private func appendRippleRings(at timestamp: TimeInterval, geo: OrbGeometry,
                                   into vertices: inout [EffectVertex]) {
        let os = orbSettings
        guard os.rippleEnabled, !ripples.isEmpty else { return }
        let step = Float.pi * 2 / Float(fanSegments)

        for birth in ripples {
            let age = Float(timestamp - birth)
            let fade = max(0, 1 - age * Float(os.rippleDecay))
            guard fade > 0 else { continue }
            let r = geo.baseRadius * (Float(os.outerRadiusMultiplier) + Float(os.rippleSpeed) * age)
            let color = SIMD4<Float>(currentOuterColor.x, currentOuterColor.y, currentOuterColor.z,
                                     Float(os.rippleOpacity) * fade)
            let rIn = max(0, r - rippleHalfThickness)
            let rOut = r + rippleHalfThickness

            func vert(_ angle: Float, _ radius: Float, _ edge: Float) -> EffectVertex {
                EffectVertex(position: SIMD2(geo.center.x + cos(angle) * radius,
                                             geo.center.y + sin(angle) * radius),
                             color: color, alpha: opacity, edgeDist: edge)
            }
            for k in 0..<fanSegments {
                let a0 = step * Float(k)
                let a1 = step * Float(k + 1)
                let i0 = vert(a0, rIn, -1), i1 = vert(a1, rIn, -1)
                let m0 = vert(a0, r, 0),    m1 = vert(a1, r, 0)
                let o0 = vert(a0, rOut, -1), o1 = vert(a1, rOut, -1)
                vertices.append(contentsOf: [i0, m0, i1,  i1, m0, m1,
                                             m0, o0, m1,  m1, o0, o1])
            }
        }
    }

    /// Current ripple ring radii, for the debug overlay.
    func currentRippleRadii() -> [Float] {
        let os = orbSettings
        guard os.rippleEnabled else { return [] }
        let geo = orbGeometry()
        return ripples.map {
            geo.baseRadius * (Float(os.outerRadiusMultiplier)
                              + Float(os.rippleSpeed) * Float(lastTickTime - $0))
        }
    }

    private func buildFan(center: SIMD2<Float>, radius: Float,
                          color: SIMD4<Float>, alpha: Float,
                          outerEdgeDist: Float) -> [EffectVertex] {
        let step = Float.pi * 2 / Float(fanSegments)
        let centerVert = EffectVertex(position: center, color: color, alpha: alpha, edgeDist: 0)
        var result: [EffectVertex] = []
        result.reserveCapacity(fanSegments * 3)

        for i in 0..<fanSegments {
            let a0 = step * Float(i)
            let a1 = step * Float(i + 1)
            let p0 = SIMD2<Float>(center.x + cos(a0) * radius, center.y + sin(a0) * radius)
            let p1 = SIMD2<Float>(center.x + cos(a1) * radius, center.y + sin(a1) * radius)
            result.append(centerVert)
            result.append(EffectVertex(position: p0, color: color, alpha: alpha, edgeDist: outerEdgeDist))
            result.append(EffectVertex(position: p1, color: color, alpha: alpha, edgeDist: outerEdgeDist))
        }
        return result
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

// MARK: - EffectDescriptor

extension OrbEffect {
    static let descriptor = EffectDescriptor(
        type: .orb,
        displayName: "Orb",
        iconAssetName: "orb",
        renderOrder: 20,
        makeDefaultSettings: { OrbSettings.defaults },
        settingsCodec: .make(OrbSettings.self),
        makeEffect: { size, layer, screen in
            OrbEffect(size: size, layer: layer, screen: screen)
        },
        makeSettingsView: { AnyView(OrbSettingsSection(layer: $0)) },
        pipelineSpec: PipelineSpec(
            vertexFunctionName: "orb_vertex",
            fragmentFunctionName: "orb_fragment",
            blendMode: .additive
        )
    )
}
