//
//  SpectrumEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import AppKit
import SwiftUI
import simd
import Combine

class SpectrumEffect: BaseEffect {

    // MARK: - Properties

    let binCount = 96
    private let barSpacing: CGFloat = 4

    private var smoothed: [Float] = Array(repeating: 0, count: 96)
    private var renderedHeight: [Float] = Array(repeating: 0, count: 96)
    private var lastTickTime: TimeInterval = 0
    private var lastDt: TimeInterval = 0.016

    // Peak-hold caps (bars style only): per-bar recent peak in len-space,
    // held briefly then falling linearly. Read by the debug overlay.
    var capLen: [Float] = Array(repeating: 0, count: 96)
    private var capHoldUntil: [TimeInterval] = Array(repeating: 0, count: 96)
    private let capHoldTime: TimeInterval = 0.5
    private let capFallRate: Float = 0.5   // fraction of maxExtent per second
    private let capThickness: Float = 3

    // Animation style cached on renderQueue via Combine sink so onTick never
    // touches AppSettings (an ObservableObject) from a background thread.
    private var cachedMotionStyle: MotionStyle = .smooth

    private var spectrumSettings: SpectrumSettings {
        layer.effectSettings as? SpectrumSettings ?? .defaults
    }

    override class var effectTypeName: String { "Spectrum" }

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
        capLen         = Array(repeating: 0, count: binCount)
        capHoldUntil   = Array(repeating: 0, count: binCount)
        lastTickTime   = 0
    }

    override func onTick(_ timestamp: TimeInterval) {
        guard let renderer else { return }

        let dt = lastTickTime == 0 ? 0.016 : min(timestamp - lastTickTime, 0.1)
        // Snappy = 50ms linear reach (matches the SpriteKit SKAction baseline).
        // Smooth uses a longer 180ms exponential time constant so the tail
        // is visibly distinct — matching the two modes at 50ms makes them
        // look identical to the eye at 60Hz.
        let lerpRate: Float
        switch cachedMotionStyle {
        case .snappy: lerpRate = Float(min(dt / 0.05, 1.0))
        case .smooth: lerpRate = Float(1.0 - exp(-dt / 0.18))
        }
        let powerCurve = Float(spectrumSettings.powerCurve)
        for i in 0..<binCount {
            let target = pow(smoothed[i], powerCurve)
            renderedHeight[i] += (target - renderedHeight[i]) * lerpRate
        }
        lastDt = dt
        lastTickTime = timestamp

        renderer.submit(id: id, type: .spectrum, mesh: EffectMesh(vertices: buildVertices()))
    }

    // `override` must live in the class body (Swift forbids it in extensions);
    // the geometry build lives in SpectrumEffectDebug.swift.
    override func drawDebug(into canvas: inout DebugCanvas) {
        buildSpectrumDebug(into: &canvas)
    }

    override func onAudio(_ bins: StereoBins) {
        let ss       = spectrumSettings
        let selected = selectedBins(from: bins)
        for i in 0..<smoothed.count {
            guard i < selected.count else { break }
            let coeff   = selected[i] > smoothed[i] ? Float(ss.attack) : Float(ss.release)
            smoothed[i] = smoothed[i] * (1 - coeff) + selected[i] * coeff
        }
    }

    // MARK: - Audio

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

    // MARK: - Bar Geometry (shared by the render mesh and the debug wireframe
    // in SpectrumEffectDebug.swift, so the skeleton can never drift from the
    // real bars)

    /// Layout constants for one frame, orientation-agnostic: bars run along the
    /// cross axis (x when vertical, y when horizontal) and grow along the
    /// amplitude axis from `base` toward `tipSign`.
    struct SpectrumLayout {
        let vertical: Bool
        let base: CGFloat
        let tipSign: CGFloat
        let mirror: Bool
        let style: SpectrumStyle
        let caps: Bool
        let rounded: Bool
        let maxExtent: CGFloat
        let stripLo: CGFloat
        let stripHi: CGFloat
        let barSize: CGFloat
        let stride: CGFloat
        let gain: CGFloat
    }

    /// One bar: cross-axis edges `lo`/`hi`, amplitude-axis `base`/`tip`
    /// (`tip` is below `base` for .top / .right anchors). When mirrored the
    /// bar spans both sides of the base line, so `base` sits at the opposite
    /// tip rather than on the line itself.
    struct BarFrame {
        let lo: Float
        let hi: Float
        let base: Float
        let tip: Float
    }

    func makeLayout() -> SpectrumLayout {
        let ss = spectrumSettings
        let vertical = ss.anchor == .bottom || ss.anchor == .top
        let crossSpan = vertical ? sceneSize.width : sceneSize.height
        let ampSpan   = vertical ? sceneSize.height : sceneSize.width
        let crossPos  = CGFloat(vertical ? layer.positionX : layer.positionY)
        let ampPos    = CGFloat(vertical ? layer.positionY : layer.positionX)

        let total = crossSpan * CGFloat(ss.width)
        let barSize = max(1, (total - barSpacing * CGFloat(binCount - 1)) / CGFloat(binCount))
        let stride = barSize + barSpacing
        let stripLo = (crossSpan - total) * crossPos
        return SpectrumLayout(
            vertical: vertical,
            base: ampSpan * ampPos,
            tipSign: (ss.anchor == .bottom || ss.anchor == .left) ? 1 : -1,
            mirror: ss.mirror,
            style: ss.style,
            caps: ss.capsEnabled,
            rounded: ss.roundedTips,
            maxExtent: ampSpan * CGFloat(ss.maxHeight),
            stripLo: stripLo,
            stripHi: stripLo + stride * CGFloat(binCount - 1) + barSize,
            barSize: barSize,
            stride: stride,
            gain: CGFloat(ss.gain))
    }

    /// Bar length in points; shared clamp for bars, caps, and the tip spline.
    func barLen(_ i: Int, in layout: SpectrumLayout) -> CGFloat {
        max(1, min(CGFloat(renderedHeight[i]) * layout.maxExtent * layout.gain, layout.maxExtent))
    }

    func barFrame(_ i: Int, in layout: SpectrumLayout) -> BarFrame {
        let len = barLen(i, in: layout)
        let lo = layout.stripLo + CGFloat(i) * layout.stride
        return BarFrame(lo: Float(lo),
                        hi: Float(lo + layout.barSize),
                        base: Float(layout.mirror ? layout.base - layout.tipSign * len : layout.base),
                        tip: Float(layout.base + layout.tipSign * len))
    }

    // MARK: - Tip Spline (curve / line styles; shared with the debug wireframe)

    /// One sampled point on the tip spline, in layout (cross, len) space.
    /// `u` is the fractional bin index, for continuous color.
    struct CurveSample {
        let cross: Float
        let len: Float      // clamped to [0, maxExtent]
        let u: Float        // 0 ... binCount-1
    }

    let curveSubdivisions = 8

    /// Smooth spline through the bar-tip amplitudes. 1D Catmull-Rom on len
    /// only (cross is uniform, so splining it would just reproduce lerp) —
    /// this keeps the curve a function of cross, which makes the fill strip
    /// trivially valid. Control values share barFrame's clamp so silence
    /// matches the bars' 1px stubs; samples are re-clamped to kill overshoot.
    func sampleCurve(in layout: SpectrumLayout) -> [CurveSample] {
        var lens = [Float]()
        lens.reserveCapacity(binCount)
        for i in 0..<binCount {
            lens.append(Float(barLen(i, in: layout)))
        }
        let crossLo = Float(layout.stripLo)
        let crossStep = Float(layout.stripHi - layout.stripLo) / Float(binCount - 1)
        let maxExtent = Float(layout.maxExtent)

        var samples = [CurveSample]()
        samples.reserveCapacity((binCount - 1) * curveSubdivisions + 1)
        func emit(_ u: Float, _ rawLen: Float) {
            samples.append(CurveSample(cross: crossLo + u * crossStep,
                                       len: min(max(rawLen, 0), maxExtent),
                                       u: u))
        }
        for seg in 0..<(binCount - 1) {
            let p0 = lens[max(seg - 1, 0)]
            let p3 = lens[min(seg + 2, binCount - 1)]
            for s in 0..<curveSubdivisions {
                let t = Float(s) / Float(curveSubdivisions)
                emit(Float(seg) + t, catmullRom(p0, lens[seg], lens[seg + 1], p3, t))
            }
        }
        emit(Float(binCount - 1), lens[binCount - 1])
        return samples
    }

    private func catmullRom(_ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float, _ t: Float) -> Float {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * ((2 * p1)
                    + (-p0 + p2) * t
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    /// Orientation swizzle: (cross, amp) → scene position.
    func scenePoint(cross: Float, amp: Float, in layout: SpectrumLayout) -> SIMD2<Float> {
        layout.vertical ? SIMD2(cross, amp) : SIMD2(amp, cross)
    }

    // MARK: - Vertex Building

    private func buildVertices() -> [EffectVertex] {
        let layout = makeLayout()
        switch layout.style {
        case .bars:  return buildBarVertices(in: layout)
        case .curve: return buildCurveFill(in: layout)
        case .line:  return buildCurveLine(in: layout)
        }
    }

    private func buildBarVertices(in layout: SpectrumLayout) -> [EffectVertex] {
        var vertices: [EffectVertex] = []
        vertices.reserveCapacity(binCount * 4 + (binCount - 1) * 3)

        for i in 0..<binCount {
            let color = barColorSIMD(at: Float(i))

            if layout.rounded {
                appendRoundedBar(i, color: color, layout: layout, to: &vertices)
            } else {
                let f = barFrame(i, in: layout)
                let v0, v1, v2, v3: EffectVertex
                if layout.vertical {
                    v0 = EffectVertex(position: SIMD2(f.lo, f.base), color: color, alpha: opacity, edgeDist: -1)
                    v1 = EffectVertex(position: SIMD2(f.lo, f.tip), color: color, alpha: opacity, edgeDist: +1)
                    v2 = EffectVertex(position: SIMD2(f.hi, f.base), color: color, alpha: opacity, edgeDist: -1)
                    v3 = EffectVertex(position: SIMD2(f.hi, f.tip), color: color, alpha: opacity, edgeDist: +1)
                } else {
                    v0 = EffectVertex(position: SIMD2(f.base, f.lo), color: color, alpha: opacity, edgeDist: -1)
                    v1 = EffectVertex(position: SIMD2(f.tip, f.lo), color: color, alpha: opacity, edgeDist: +1)
                    v2 = EffectVertex(position: SIMD2(f.base, f.hi), color: color, alpha: opacity, edgeDist: -1)
                    v3 = EffectVertex(position: SIMD2(f.tip, f.hi), color: color, alpha: opacity, edgeDist: +1)
                }
                appendBar(to: &vertices, v0: v0, v1: v1, v2: v2, v3: v3)
            }

            if layout.caps {
                updateCap(i, in: layout)
                appendCapQuads(i, color: color, layout: layout, to: &vertices)
            }
        }

        return vertices
    }

    /// Rounded-tip bar as a column strip: 9 cross samples, the tip edge walks
    /// a semi-ellipse (semi-axes barSize/2 across, min(barSize/2, len) along
    /// amp — squashes flat instead of inverting when the bar is shorter than
    /// its radius). Mirrored bars round both ends.
    private func appendRoundedBar(_ i: Int, color: SIMD4<Float>,
                                  layout: SpectrumLayout, to vertices: inout [EffectVertex]) {
        let columns = 8
        let len = Float(barLen(i, in: layout))
        let lo = Float(layout.stripLo + CGFloat(i) * layout.stride)
        let halfW = Float(layout.barSize) / 2
        let mid = lo + halfW
        let inset = min(halfW, len)
        let base = Float(layout.base)
        let tipSign = Float(layout.tipSign)

        for k in 0...columns {
            let u = Float(k) / Float(columns) * 2 - 1          // -1 ... +1 across the bar
            let cross = mid + u * halfW
            let bulge = (len - inset) + inset * sqrt(max(0, 1 - u * u))
            let tipAmp = base + tipSign * bulge
            let lowAmp = layout.mirror ? base - tipSign * bulge : base
            let v0 = EffectVertex(position: scenePoint(cross: cross, amp: lowAmp, in: layout),
                                  color: color, alpha: opacity, edgeDist: -1)
            let v1 = EffectVertex(position: scenePoint(cross: cross, amp: tipAmp, in: layout),
                                  color: color, alpha: opacity, edgeDist: +1)
            if k == 0, let lastV = vertices.last {
                vertices.append(lastV)
                vertices.append(lastV)
                vertices.append(v0)
            }
            vertices.append(v0)
            vertices.append(v1)
        }
    }

    // MARK: - Peak-hold caps

    private func updateCap(_ i: Int, in layout: SpectrumLayout) {
        let len = Float(barLen(i, in: layout))
        if len >= capLen[i] {
            capLen[i] = len
            capHoldUntil[i] = lastTickTime + capHoldTime
        } else if lastTickTime > capHoldUntil[i] {
            capLen[i] = max(len, capLen[i] - capFallRate * Float(layout.maxExtent) * Float(lastDt))
        }
    }

    /// Small floating quad at the held peak, brightened toward white so it
    /// reads as a marker; mirrored bars get one on each side.
    private func appendCapQuads(_ i: Int, color: SIMD4<Float>,
                                layout: SpectrumLayout, to vertices: inout [EffectVertex]) {
        let capColor = color + (SIMD4<Float>(1, 1, 1, color.w) - color) * 0.5
        let lo = Float(layout.stripLo + CGFloat(i) * layout.stride)
        let hi = lo + Float(layout.barSize)
        let base = Float(layout.base)
        let tipSign = Float(layout.tipSign)

        func emit(side: Float) {
            let inner = base + side * tipSign * capLen[i]
            let outer = inner + side * tipSign * capThickness
            let v0 = EffectVertex(position: scenePoint(cross: lo, amp: inner, in: layout),
                                  color: capColor, alpha: opacity, edgeDist: 0)
            let v1 = EffectVertex(position: scenePoint(cross: lo, amp: outer, in: layout),
                                  color: capColor, alpha: opacity, edgeDist: 0)
            let v2 = EffectVertex(position: scenePoint(cross: hi, amp: inner, in: layout),
                                  color: capColor, alpha: opacity, edgeDist: 0)
            let v3 = EffectVertex(position: scenePoint(cross: hi, amp: outer, in: layout),
                                  color: capColor, alpha: opacity, edgeDist: 0)
            appendBar(to: &vertices, v0: v0, v1: v1, v2: v2, v3: v3)
        }
        emit(side: +1)
        if layout.mirror { emit(side: -1) }
    }

    /// Filled mountain silhouette: one continuous strip, two vertices per
    /// sampled column (lower edge / curve). No degenerate stitching needed —
    /// the 1D spline guarantees one column per cross position.
    private func buildCurveFill(in layout: SpectrumLayout) -> [EffectVertex] {
        let samples = sampleCurve(in: layout)
        let base = Float(layout.base)
        let tipSign = Float(layout.tipSign)
        var verts = [EffectVertex]()
        verts.reserveCapacity(samples.count * 2)
        for s in samples {
            let color = barColorSIMD(at: s.u)
            let lowAmp = layout.mirror ? base - tipSign * s.len : base
            let tipAmp = base + tipSign * s.len
            verts.append(EffectVertex(position: scenePoint(cross: s.cross, amp: lowAmp, in: layout),
                                      color: color, alpha: opacity, edgeDist: -1))
            verts.append(EffectVertex(position: scenePoint(cross: s.cross, amp: tipAmp, in: layout),
                                      color: color, alpha: opacity, edgeDist: +1))
        }
        return verts
    }

    /// 3pt stroke along the spline. True 2D normal offset (not amp-axis) so
    /// steep powerCurve spikes keep constant apparent width. Mirror = second
    /// strip joined with the same degenerate stitch appendBar uses.
    private let lineHalfWidth: Float = 1.5

    private func buildCurveLine(in layout: SpectrumLayout) -> [EffectVertex] {
        let samples = sampleCurve(in: layout)
        let base = Float(layout.base)
        let tipSign = Float(layout.tipSign)
        var verts = [EffectVertex]()
        verts.reserveCapacity(samples.count * 2 * (layout.mirror ? 2 : 1) + 3)

        func appendStroke(side: Float) {
            var pts = [SIMD2<Float>]()
            pts.reserveCapacity(samples.count)
            for s in samples {
                pts.append(scenePoint(cross: s.cross, amp: base + side * tipSign * s.len, in: layout))
            }
            for k in pts.indices {
                var tangent = pts[min(k + 1, pts.count - 1)] - pts[max(k - 1, 0)]
                let m = simd_length(tangent)
                tangent = m > 0 ? tangent / m : SIMD2(1, 0)
                let normal = SIMD2(-tangent.y, tangent.x) * lineHalfWidth
                let color = barColorSIMD(at: samples[k].u)
                let a = EffectVertex(position: pts[k] + normal, color: color, alpha: opacity, edgeDist: +1)
                let b = EffectVertex(position: pts[k] - normal, color: color, alpha: opacity, edgeDist: -1)
                if k == 0, let lastV = verts.last {
                    verts.append(lastV)
                    verts.append(lastV)
                    verts.append(a)
                }
                verts.append(a)
                verts.append(b)
            }
        }
        appendStroke(side: +1)
        if layout.mirror { appendStroke(side: -1) }
        return verts
    }

    private func appendBar(to vertices: inout [EffectVertex],
                           v0: EffectVertex, v1: EffectVertex,
                           v2: EffectVertex, v3: EffectVertex) {
        if let lastV = vertices.last {
            vertices.append(lastV)
            vertices.append(lastV)
            vertices.append(v0)
        }
        vertices.append(contentsOf: [v0, v1, v2, v3])
    }

    // MARK: - Color Calculation (alloc-free)

    /// `u` is a fractional bin index so the curve/line styles get continuous
    /// color; bars call with whole numbers and get the exact pre-fractional
    /// output. The stereo palette switch at u = half−0.5 lands on the seam
    /// midpoint, equivalent to the old `i >= half` for integers.
    private func barColorSIMD(at u: Float) -> SIMD4<Float> {
        let ss = spectrumSettings
        let isRight = layer.channelMode == .stereo && CGFloat(u) >= CGFloat(binCount / 2) - 0.5
        let cs: ChannelColorSettings
        if layer.channelMode == .stereo && !ss.colorSync {
            cs = isRight ? ss.rightColorSettings : ss.leftColorSettings
        } else {
            cs = ss.colorSettings
        }
        switch cs.colorMode {
        case .rainbow:
            let hue = Float(0.6 - rainbowRatio(at: CGFloat(u)) * 0.5)
            return hsbToRGBA(h: hue, s: 0.8, b: 1.0, a: 1.0)
        case .gradient:
            let t = Float(gradientRatio(at: CGFloat(u)))
            let lo = SIMD4<Float>(Float(cs.gradientColorLow.red), Float(cs.gradientColorLow.green),
                                  Float(cs.gradientColorLow.blue), Float(cs.gradientColorLow.alpha))
            let hi = SIMD4<Float>(Float(cs.gradientColorHigh.red), Float(cs.gradientColorHigh.green),
                                  Float(cs.gradientColorHigh.blue), Float(cs.gradientColorHigh.alpha))
            return lo + (hi - lo) * t
        case .solid:
            return SIMD4<Float>(Float(cs.solidColor.red), Float(cs.solidColor.green),
                                Float(cs.solidColor.blue), Float(cs.solidColor.alpha))
        }
    }

    private func rainbowRatio(at u: CGFloat) -> CGFloat {
        if layer.channelMode == .stereo {
            let half = CGFloat(binCount / 2)
            let r = u < half - 0.5
                ? u / (half - 1)
                : 1.0 - (u - half) / (half - 1)
            return min(max(r, 0), 1)
        }
        // Divides by binCount (not binCount-1) — existing inconsistency with
        // gradientRatio, preserved so bars don't shift hue.
        return u / CGFloat(binCount)
    }

    private func gradientRatio(at u: CGFloat) -> CGFloat {
        if layer.channelMode == .stereo {
            let half = CGFloat(binCount / 2)
            let r = u < half - 0.5
                ? u / (half - 1)
                : 1.0 - (u - half) / (half - 1)
            return min(max(r, 0), 1)
        }
        return u / CGFloat(binCount - 1)
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

extension SpectrumEffect {
    static let descriptor = EffectDescriptor(
        type: .spectrum,
        displayName: "Spectrum",
        iconAssetName: "spectrum",
        renderOrder: 10,
        makeDefaultSettings: { SpectrumSettings.defaults },
        settingsCodec: .make(SpectrumSettings.self),
        makeEffect: { size, layer, screen in
            SpectrumEffect(size: size, layer: layer, screen: screen)
        },
        makeSettingsView: { AnyView(SpectrumSettingsSection(layer: $0)) },
        pipelineSpec: PipelineSpec(
            vertexFunctionName: "spectrum_vertex",
            fragmentFunctionName: "spectrum_fragment",
            blendMode: .alphaBlend
        )
    )
}
