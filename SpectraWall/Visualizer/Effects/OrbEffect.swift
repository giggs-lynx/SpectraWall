//
//  OrbEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import AppKit
import SwiftUI
import simd

class OrbEffect: BaseEffect {

    // MARK: - Properties

    private var smoothedLeft:  Float = 0
    private var smoothedRight: Float = 0

    // Derived from audio each callback; read in onTick (same renderQueue).
    private var currentScale:      Float = 0
    private var currentInnerColor: SIMD4<Float> = SIMD4(0.2, 0.4, 1.0, 1.0)
    private var currentOuterColor: SIMD4<Float> = SIMD4(0.2, 0.4, 1.0, 0.15)

    // Lerped display values — inner 50ms, outer 80ms (matches SKAction durations)
    private var renderedInnerScale: Float = 0
    private var renderedOuterScale: Float = 0
    private var lastTickTime: TimeInterval = 0

    private var orbSettings: OrbSettings {
        layer.effectSettings as? OrbSettings ?? .defaults
    }

    private let fanSegments = 32

    override class var effectTypeName: String { "Orb" }

    // MARK: - BaseEffect hooks

    override func onReset() {
        smoothedLeft       = 0
        smoothedRight      = 0
        currentScale       = 0
        renderedInnerScale = 0
        renderedOuterScale = 0
        lastTickTime       = 0
    }

    override func onTick(_ timestamp: TimeInterval) {
        guard let renderer else { return }

        let dt = lastTickTime == 0 ? 0.016 : min(timestamp - lastTickTime, 0.1)
        renderedInnerScale += (currentScale - renderedInnerScale) * Float(1.0 - exp(-dt / 0.05))
        renderedOuterScale += (currentScale - renderedOuterScale) * Float(1.0 - exp(-dt / 0.08))
        lastTickTime = timestamp

        renderer.submit(id: id, type: .orb, mesh: buildOrbData())
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
        let peakAmp = max(bins.left.max() ?? 0, bins.right.max() ?? 0)
        let silenceLo: Float = 0.001
        let silenceHi: Float = 0.01
        let t = (peakAmp - silenceLo) / (silenceHi - silenceLo)
        let clampedT = max(0, min(1, t))
        let silenceGate = clampedT * clampedT * (3 - 2 * clampedT)
        currentScale = silenceGate * min(1.0 + amplitude * Float(os.boost), 2.5)

        let intensity = bins.amplitude(for: layer.channelMode, binRange: 0..<4)
        currentInnerColor = lerpColor(from: os.innerColorLow, to: os.innerColorHigh, t: intensity)
        currentOuterColor = lerpColor(from: os.outerColorLow, to: os.outerColorHigh, t: intensity,
                                      alphaOverride: Float(os.outerOpacity))
    }

    // MARK: - Vertex Building

    private func buildOrbData() -> EffectMesh {
        let os = orbSettings
        let cx = Float(sceneSize.width  * layer.positionX)
        let cy = Float(sceneSize.height * layer.positionY)
        let center = SIMD2<Float>(cx, cy)

        let innerR = Float(os.baseRadius) * renderedInnerScale
        let outerR = Float(os.baseRadius) * renderedOuterScale * Float(os.outerRadiusMultiplier)

        var vertices: [EffectVertex] = []
        vertices.reserveCapacity(fanSegments * 3 * 2)

        // Outer glow first (drawn underneath inner orb); negative edgeDist = glow mode in shader
        appendFan(to: &vertices, center: center, radius: outerR,
                  color: currentOuterColor, alpha: opacity, outerEdgeDist: -1)

        // Inner solid disk on top; positive edgeDist = solid-disk mode in shader
        appendFan(to: &vertices, center: center, radius: innerR,
                  color: currentInnerColor, alpha: opacity, outerEdgeDist: +1)

        return EffectMesh(vertices: vertices, primitiveType: .triangle)
    }

    private func appendFan(to vertices: inout [EffectVertex],
                            center: SIMD2<Float>, radius: Float,
                            color: SIMD4<Float>, alpha: Float,
                            outerEdgeDist: Float) {
        let step = Float.pi * 2 / Float(fanSegments)
        let centerVert = EffectVertex(position: center, color: color, alpha: alpha, edgeDist: 0)

        for i in 0..<fanSegments {
            let a0 = step * Float(i)
            let a1 = step * Float(i + 1)
            let p0 = SIMD2<Float>(center.x + cos(a0) * radius, center.y + sin(a0) * radius)
            let p1 = SIMD2<Float>(center.x + cos(a1) * radius, center.y + sin(a1) * radius)
            vertices.append(centerVert)
            vertices.append(EffectVertex(position: p0, color: color, alpha: alpha, edgeDist: outerEdgeDist))
            vertices.append(EffectVertex(position: p1, color: color, alpha: alpha, edgeDist: outerEdgeDist))
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
