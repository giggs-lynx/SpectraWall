//
//  RadialSpectrumEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/6/11.
//
//  96 semitone bins arranged around a circle, growing radially from a hub.
//  Stereo splits left/right half-circles mirror-symmetrically with low
//  frequencies at 12 o'clock descending both sides; other channel modes run
//  the full circle clockwise from the top.
//

import AppKit
import SwiftUI
import simd
import Combine

class RadialSpectrumEffect: BaseEffect {

    // MARK: - Properties

    let binCount = 96
    /// Fraction of each bar's angular slot left as a gap to its neighbour.
    private let angularGap: Float = 0.2
    /// Mirrored bars never reach deeper inward than this fraction of the hub
    /// radius, so they can't fold through the centre.
    private let minInwardHubFraction: Float = 0.2

    private var smoothed: [Float] = Array(repeating: 0, count: 96)
    private var renderedHeight: [Float] = Array(repeating: 0, count: 96)
    private var lastTickTime: TimeInterval = 0

    private var cachedMotionStyle: MotionStyle = .smooth

    private var radialSettings: RadialSpectrumSettings {
        layer.effectSettings as? RadialSpectrumSettings ?? .defaults
    }

    override class var effectTypeName: String { "RadialSpectrum" }

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
        smoothed       = Array(repeating: 0, count: binCount)
        renderedHeight = Array(repeating: 0, count: binCount)
        lastTickTime   = 0
    }

    override func onTick(_ timestamp: TimeInterval) {
        guard let renderer else { return }

        let dt = lastTickTime == 0 ? 0.016 : min(timestamp - lastTickTime, 0.1)
        let lerpRate: Float
        switch cachedMotionStyle {
        case .snappy: lerpRate = Float(min(dt / 0.05, 1.0))
        case .smooth: lerpRate = Float(1.0 - exp(-dt / 0.18))
        }
        let powerCurve = Float(radialSettings.powerCurve)
        for i in 0..<binCount {
            let target = pow(smoothed[i], powerCurve)
            renderedHeight[i] += (target - renderedHeight[i]) * lerpRate
        }
        lastTickTime = timestamp

        renderer.submit(id: id, type: .radialSpectrum,
                        mesh: EffectMesh(vertices: buildVertices()))
    }

    override func onAudio(_ bins: StereoBins) {
        let rs       = radialSettings
        let selected = selectedBins(from: bins)
        for i in 0..<smoothed.count {
            guard i < selected.count else { break }
            let coeff   = selected[i] > smoothed[i] ? Float(rs.attack) : Float(rs.release)
            smoothed[i] = smoothed[i] * (1 - coeff) + selected[i] * coeff
        }
    }

    override func drawDebug(into canvas: inout DebugCanvas) {
        buildRadialDebug(into: &canvas)
    }

    // MARK: - Audio

    /// Display order matches Spectrum: stereo = left ascending + right
    /// reversed, so the centre seam carries both channels' highs — here the
    /// "seam" is the bottom of the circle.
    private func selectedBins(from stereo: StereoBins) -> [Float] {
        switch layer.channelMode {
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

    // MARK: - Geometry (shared with the debug wireframe)

    struct RadialGeometry {
        let center: SIMD2<Float>
        let hubRadius: Float
        let maxExtent: Float
        let mirror: Bool
    }

    func radialGeometry() -> RadialGeometry {
        let rs = radialSettings
        return RadialGeometry(
            center: SIMD2(Float(sceneSize.width * layer.positionX),
                          Float(sceneSize.height * layer.positionY)),
            hubRadius: Float(rs.innerRadius),
            maxExtent: Float(rs.maxExtent),
            mirror: rs.mirror)
    }

    /// Centre angle for display index `i`. Stereo: left bins sweep the left
    /// half-circle from the top down, right bins mirror on the right. Other
    /// modes sweep the full circle clockwise from the top.
    func barAngle(_ i: Int) -> Float {
        let half = binCount / 2
        if layer.channelMode == .stereo {
            // Display order is [L0...L47, R47...R0]; map so lows sit at the
            // top on both sides and highs meet at the bottom seam.
            if i < half {
                return .pi / 2 + (Float(i) + 0.5) / Float(half) * .pi
            } else {
                return .pi / 2 - (Float(binCount - 1 - i) + 0.5) / Float(half) * .pi
            }
        }
        return .pi / 2 - (Float(i) + 0.5) / Float(binCount) * 2 * .pi
    }

    func barLength(_ i: Int, geo: RadialGeometry) -> Float {
        let gain = Float(radialSettings.gain)
        return max(1, min(renderedHeight[i] * geo.maxExtent * gain, geo.maxExtent))
    }

    /// Radial span of bar `i`: outward tip, and the inner edge (hub radius,
    /// or mirrored inward with a clamp so bars never fold through the centre).
    func barRadialSpan(_ i: Int, geo: RadialGeometry) -> (rIn: Float, rOut: Float) {
        let len = barLength(i, geo: geo)
        let rOut = geo.hubRadius + len
        let rIn = geo.mirror
            ? max(geo.hubRadius * minInwardHubFraction, geo.hubRadius - len)
            : geo.hubRadius
        return (rIn, rOut)
    }

    // MARK: - Vertex Building

    private func buildVertices() -> [EffectVertex] {
        let geo = radialGeometry()
        let halfSlot = Float.pi / Float(binCount) * (1 - angularGap)

        var vertices: [EffectVertex] = []
        vertices.reserveCapacity(binCount * 4 + (binCount - 1) * 3)

        for i in 0..<binCount {
            let angle = barAngle(i)
            let (rIn, rOut) = barRadialSpan(i, geo: geo)
            let color = barColorSIMD(for: i)
            let a0 = angle - halfSlot
            let a1 = angle + halfSlot

            func vert(_ a: Float, _ r: Float, _ edge: Float) -> EffectVertex {
                EffectVertex(position: SIMD2(geo.center.x + cos(a) * r,
                                             geo.center.y + sin(a) * r),
                             color: color, alpha: opacity, edgeDist: edge)
            }
            let v0 = vert(a0, rIn, -1)
            let v1 = vert(a0, rOut, +1)
            let v2 = vert(a1, rIn, -1)
            let v3 = vert(a1, rOut, +1)
            if let lastV = vertices.last {
                vertices.append(lastV)
                vertices.append(lastV)
                vertices.append(v0)
            }
            vertices.append(contentsOf: [v0, v1, v2, v3])
        }
        return vertices
    }

    // MARK: - Color

    private func barColorSIMD(for index: Int) -> SIMD4<Float> {
        let rs = radialSettings
        let half = binCount / 2
        let isRight = layer.channelMode == .stereo && index >= half
        let cs: ChannelColorSettings
        if layer.channelMode == .stereo && !rs.colorSync {
            cs = isRight ? rs.rightColorSettings : rs.leftColorSettings
        } else {
            cs = rs.colorSettings
        }
        // 0 at low frequency, 1 at high; stereo folds so both sides match.
        let ratio: Float
        if layer.channelMode == .stereo {
            ratio = index < half
                ? Float(index) / Float(half - 1)
                : Float(binCount - 1 - index) / Float(half - 1)
        } else {
            ratio = Float(index) / Float(binCount - 1)
        }
        switch cs.colorMode {
        case .rainbow:
            return hsbToRGBA(h: 0.6 - ratio * 0.5, s: 0.8, b: 1.0, a: 1.0)
        case .gradient:
            let lo = SIMD4<Float>(Float(cs.gradientColorLow.red), Float(cs.gradientColorLow.green),
                                  Float(cs.gradientColorLow.blue), Float(cs.gradientColorLow.alpha))
            let hi = SIMD4<Float>(Float(cs.gradientColorHigh.red), Float(cs.gradientColorHigh.green),
                                  Float(cs.gradientColorHigh.blue), Float(cs.gradientColorHigh.alpha))
            return lo + (hi - lo) * ratio
        case .solid:
            return SIMD4<Float>(Float(cs.solidColor.red), Float(cs.solidColor.green),
                                Float(cs.solidColor.blue), Float(cs.solidColor.alpha))
        }
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

// MARK: - EffectDescriptor

extension RadialSpectrumEffect {
    static let descriptor = EffectDescriptor(
        type: .radialSpectrum,
        displayName: "Radial",
        iconAssetName: "spectrum",   // TODO: dedicated icon; reusing spectrum's for now
        renderOrder: 15,
        makeDefaultSettings: { RadialSpectrumSettings.defaults },
        settingsCodec: .make(RadialSpectrumSettings.self),
        makeEffect: { size, layer, screen in
            RadialSpectrumEffect(size: size, layer: layer, screen: screen)
        },
        makeSettingsView: { AnyView(RadialSpectrumSettingsSection(layer: $0)) },
        pipelineSpec: PipelineSpec(
            vertexFunctionName: "spectrum_vertex",
            fragmentFunctionName: "spectrum_fragment",
            blendMode: .alphaBlend
        )
    )
}
