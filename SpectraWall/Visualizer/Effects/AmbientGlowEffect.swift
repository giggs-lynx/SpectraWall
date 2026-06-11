//
//  AmbientGlowEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/6/11.
//
//  Soft additive haze pinned to the screen edges that breathes with the low
//  band — "fog" where Border is "line". Geometry is a handful of quads with
//  the fade done in glow_fragment (smoothstep over edgeDist), so the fill is
//  band-free at any size.
//

import AppKit
import SwiftUI
import simd
import Combine

class AmbientGlowEffect: BaseEffect {

    // MARK: - Properties

    private var smoothedAmp: Float = 0
    private var currentGate: Float = 0
    private var currentColor: SIMD4<Float> = SIMD4(0.1, 0.2, 0.6, 1)
    private var renderedLevel: Float = 0
    private var lastTickTime: TimeInterval = 0

    private var glowSettings: AmbientGlowSettings {
        layer.effectSettings as? AmbientGlowSettings ?? .defaults
    }

    override class var effectTypeName: String { "AmbientGlow" }

    // MARK: - BaseEffect hooks

    override func onReset() {
        smoothedAmp   = 0
        currentGate   = 0
        renderedLevel = 0
        lastTickTime  = 0
    }

    override func onAudio(_ bins: StereoBins) {
        let gs = glowSettings
        let amp = bins.amplitude(for: layer.channelMode)   // low band, like Orb
        let coeff = amp > smoothedAmp ? Float(gs.attack) : Float(gs.release)
        smoothedAmp = smoothedAmp * (1 - coeff) + amp * coeff

        // Same full-spectrum silence gate as Orb so the haze vanishes in
        // silence instead of idling at colorLow.
        let t = (bins.peak - SilenceThreshold.enter) / (SilenceThreshold.exit - SilenceThreshold.enter)
        let clampedT = max(0, min(1, t))
        currentGate = clampedT * clampedT * (3 - 2 * clampedT)

        let mix = min(smoothedAmp * 2, 1)
        currentColor = lerpColor(from: gs.colorLow, to: gs.colorHigh, t: mix)
    }

    override func onTick(_ timestamp: TimeInterval) {
        guard let renderer else { return }

        let dt = lastTickTime == 0 ? 0.016 : min(timestamp - lastTickTime, 0.1)
        let target = currentGate * min(smoothedAmp * 2, 1)
        renderedLevel += (target - renderedLevel) * Float(1.0 - exp(-dt / 0.18))
        lastTickTime = timestamp

        renderer.submit(id: id, type: .ambientGlow,
                        mesh: EffectMesh(vertices: buildVertices(), primitiveType: .triangle))
    }

    override func drawDebug(into canvas: inout DebugCanvas) {
        let inset = CGFloat(glowDepth())
        let w = sceneSize.width
        let h = sceneSize.height
        let color = SIMD4<Float>(0, 1, 0, 1)
        switch glowSettings.placement {
        case .edges:
            canvas.polyline([CGPoint(x: inset, y: inset), CGPoint(x: w - inset, y: inset),
                             CGPoint(x: w - inset, y: h - inset), CGPoint(x: inset, y: h - inset),
                             CGPoint(x: inset, y: inset)], color: color, width: 1.5)
        case .bottom:
            canvas.segment(CGPoint(x: 0, y: inset), CGPoint(x: w, y: inset), color: color, width: 1.5)
        case .top:
            canvas.segment(CGPoint(x: 0, y: h - inset), CGPoint(x: w, y: h - inset), color: color, width: 1.5)
        }
    }

    // MARK: - Geometry

    private func glowDepth() -> Float {
        Float(min(sceneSize.width, sceneSize.height)) * Float(glowSettings.size)
    }

    private func buildVertices() -> [EffectVertex] {
        let gs = glowSettings
        let level = renderedLevel
        guard level > 0.001 else { return [] }

        let color = SIMD4<Float>(currentColor.x, currentColor.y, currentColor.z,
                                 Float(gs.intensity) * level)
        let w = Float(sceneSize.width)
        let h = Float(sceneSize.height)
        let d = glowDepth()

        // outer = screen edge (edgeDist 1, full glow); inner = inset (edgeDist 0).
        func vert(_ x: Float, _ y: Float, _ edge: Float) -> EffectVertex {
            EffectVertex(position: SIMD2(x, y), color: color, alpha: opacity, edgeDist: edge)
        }
        func quad(_ a: EffectVertex, _ b: EffectVertex, _ c: EffectVertex, _ dv: EffectVertex) -> [EffectVertex] {
            [a, b, c, c, b, dv]
        }

        switch gs.placement {
        case .bottom:
            return quad(vert(0, 0, 1), vert(w, 0, 1), vert(0, d, 0), vert(w, d, 0))
        case .top:
            return quad(vert(0, h, 1), vert(w, h, 1), vert(0, h - d, 0), vert(w, h - d, 0))
        case .edges:
            // Four trapezoids with 45° mitred corners: no overlap, so the
            // additive blend doesn't double-brighten the corners.
            var verts: [EffectVertex] = []
            verts.reserveCapacity(24)
            // bottom
            verts += quad(vert(0, 0, 1), vert(w, 0, 1), vert(d, d, 0), vert(w - d, d, 0))
            // top
            verts += quad(vert(0, h, 1), vert(w, h, 1), vert(d, h - d, 0), vert(w - d, h - d, 0))
            // left
            verts += quad(vert(0, 0, 1), vert(0, h, 1), vert(d, d, 0), vert(d, h - d, 0))
            // right
            verts += quad(vert(w, 0, 1), vert(w, h, 1), vert(w - d, d, 0), vert(w - d, h - d, 0))
            return verts
        }
    }

    // MARK: - Color Helpers

    private func lerpColor(from lo: ColorData, to hi: ColorData, t: Float) -> SIMD4<Float> {
        let r = Float(lo.red)   + (Float(hi.red)   - Float(lo.red))   * t
        let g = Float(lo.green) + (Float(hi.green) - Float(lo.green)) * t
        let b = Float(lo.blue)  + (Float(hi.blue)  - Float(lo.blue))  * t
        return SIMD4(r, g, b, 1)
    }
}

// MARK: - EffectDescriptor

extension AmbientGlowEffect {
    static let descriptor = EffectDescriptor(
        type: .ambientGlow,
        displayName: "Glow",
        iconAssetName: "border",   // TODO: dedicated icon; reusing border's for now
        renderOrder: 5,
        commonSettings: [.opacity, .channelMode],   // pinned to screen edges; position has no meaning
        makeDefaultSettings: { AmbientGlowSettings.defaults },
        settingsCodec: .make(AmbientGlowSettings.self),
        makeEffect: { size, layer, screen in
            AmbientGlowEffect(size: size, layer: layer, screen: screen)
        },
        makeSettingsView: { AnyView(AmbientGlowSettingsSection(layer: $0)) },
        pipelineSpec: PipelineSpec(
            vertexFunctionName: "spectrum_vertex",
            fragmentFunctionName: "glow_fragment",
            blendMode: .additive
        )
    )
}
