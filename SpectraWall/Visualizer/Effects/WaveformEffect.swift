//
//  WaveformEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/6/11.
//
//  Scrolling amplitude band (soundcloud-style envelope): each tap buffer
//  becomes one column of per-channel peak amplitude; the band streams right
//  to left across the strip. Raw PCM arrives via waveformPublisher and is
//  reduced to columns on the render queue, never the audio thread.
//

import AppKit
import SwiftUI
import simd
import Combine

class WaveformEffect: BaseEffect {

    // MARK: - Column ring buffer

    private struct Column {
        var left: Float = 0
        var right: Float = 0
    }

    private let ringCapacity = 1024
    private var columns: [Column]
    /// Total columns ever written; writeCount % ringCapacity is the next slot.
    private var writeCount = 0

    /// Tap callback cadence (~94Hz at 512-sample buffers / 48kHz). Used to map
    /// windowSeconds → column count; an EMA over observed arrivals keeps the
    /// scroll speed right even if the buffer size differs.
    private var columnsPerSecond: Double = 94
    private var lastIngestTime: TimeInterval = 0

    private var waveformSettings: WaveformSettings {
        layer.effectSettings as? WaveformSettings ?? .defaults
    }

    override class var effectTypeName: String { "Waveform" }

    // MARK: - Lifecycle

    override init(size: CGSize, layer: LayerSettings, screen: NSScreen) {
        columns = Array(repeating: Column(), count: ringCapacity)
        super.init(size: size, layer: layer, screen: screen)
        let queue: DispatchQueue = renderer?.renderQueue ?? .main
        AudioDataBus.shared.waveformPublisher
            .receive(on: queue)
            .sink { [weak self] samples in self?.ingest(left: samples.left, right: samples.right) }
            .store(in: &cancellables)
    }

    // MARK: - BaseEffect hooks

    override func onReset() {
        columns = Array(repeating: Column(), count: ringCapacity)
        writeCount = 0
        lastIngestTime = 0
    }

    override func onAudio(_ bins: StereoBins) {
        // Waveform consumes raw PCM via waveformPublisher, not the FFT bins.
    }

    override func onTick(_ timestamp: TimeInterval) {
        guard let renderer else { return }
        renderer.submit(id: id, type: .waveform,
                        mesh: EffectMesh(vertices: buildVertices()))
    }

    override func drawDebug(into canvas: inout DebugCanvas) {
        let frame = stripFrame()
        let color = SIMD4<Float>(0, 1, 0, 1)
        canvas.segment(CGPoint(x: frame.minX, y: frame.midY),
                       CGPoint(x: frame.maxX, y: frame.midY), color: color, width: 1.5)
        canvas.polyline([CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                         CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY),
                         CGPoint(x: frame.minX, y: frame.minY)], color: SIMD4<Float>(1, 0, 1, 1), width: 1.5)
    }

    // MARK: - Ingest (render queue)

    private func ingest(left: [Float], right: [Float]) {
        var maxL: Float = 0
        for v in left { maxL = max(maxL, abs(v)) }
        var maxR: Float = 0
        for v in right { maxR = max(maxR, abs(v)) }
        columns[writeCount % ringCapacity] = Column(left: maxL, right: maxR)
        writeCount += 1

        // EMA over the arrival interval keeps windowSeconds honest.
        let now = CACurrentMediaTime()
        if lastIngestTime > 0 {
            let dt = now - lastIngestTime
            if dt > 0.001, dt < 0.1 {
                columnsPerSecond = columnsPerSecond * 0.95 + (1 / dt) * 0.05
            }
        }
        lastIngestTime = now
    }

    // MARK: - Geometry

    private func stripFrame() -> CGRect {
        let h = sceneSize.height * CGFloat(waveformSettings.maxHeight)
        let centerY = sceneSize.height * layer.positionY
        return CGRect(x: 0, y: centerY - h, width: sceneSize.width, height: h * 2)
    }

    private func buildVertices() -> [EffectVertex] {
        let ws = waveformSettings
        let visible = min(ringCapacity, max(2, Int(ws.windowSeconds * columnsPerSecond)))
        guard writeCount > 0 else { return [] }

        let width = Float(sceneSize.width)
        let height = Float(sceneSize.height)
        let centerY = height * Float(layer.positionY)
        let span = height * Float(ws.maxHeight)
        // Clamp the reachable amplitude to the distance from the centerline to
        // each screen edge, so a full-scale peak sits flush against the border
        // rather than being clipped off (or flat-topped).
        let upSpan = min(span, height - centerY)
        let downSpan = min(span, centerY)
        let gain = Float(ws.gain)

        // Stereo: left band above the centerline, right mirrored below.
        // Other modes: one band symmetric around the centerline.
        let stereo = layer.channelMode == .stereo

        // Normalized (0...1) per-channel amplitude; scaled by the directional
        // span at vertex time so up/down each respect their own headroom.
        func amp(_ c: Column) -> (up: Float, down: Float) {
            switch layer.channelMode {
            case .stereo: return (min(c.left * gain, 1), min(c.right * gain, 1))
            case .left:   let a = min(c.left * gain, 1);  return (a, a)
            case .right:  let a = min(c.right * gain, 1); return (a, a)
            case .mono:   let a = min((c.left + c.right) / 2 * gain, 1); return (a, a)
            }
        }

        // Pixel-grid params ride in segA/radius (see spectrum_fragment); segA.y
        // is the 1px line width. radius == 0 disables the overlay per-vertex.
        let gridOpacity = ws.pixelGridEnabled ? Float(ws.pixelGridOpacity) : 0
        let gridSeg = SIMD2<Float>(Float(ws.pixelGridSpacing), 1)

        var verts: [EffectVertex] = []
        verts.reserveCapacity(visible * 4 + 3)
        var topPoints: [SIMD2<Float>] = []
        if ws.peakOutlineEnabled { topPoints.reserveCapacity(visible) }

        for k in 0..<visible {
            let columnIndex = writeCount - visible + k
            let c = columnIndex >= 0 ? columns[columnIndex % ringCapacity] : Column()
            let x = width * (Float(k) + 0.5) / Float(visible)
            let (upN, downN) = amp(c)
            let intensity = stereo ? max(upN, downN) : upN
            let color = columnColor(x: x / width, intensity: intensity)
            // Hairline floor so the strip stays visible in silence.
            let yTop = centerY + max(upN * upSpan, 0.5)
            let yBot = centerY - max(downN * downSpan, 0.5)
            verts.append(EffectVertex(position: SIMD2(x, yBot), color: color, alpha: opacity,
                                      edgeDist: -1, segA: gridSeg, radius: gridOpacity))
            verts.append(EffectVertex(position: SIMD2(x, yTop), color: color, alpha: opacity,
                                      edgeDist: +1, segA: gridSeg, radius: gridOpacity))
            if ws.peakOutlineEnabled { topPoints.append(SIMD2(x, yTop)) }
        }

        if ws.peakOutlineEnabled {
            appendTopOutline(points: topPoints,
                             halfWidth: Float(ws.peakOutlineWidth) / 2, to: &verts)
        }
        return verts
    }

    /// White constant-width stroke along the top peak envelope, joined to the
    /// band strip with a degenerate stitch. Grid fields stay zero so the line
    /// never picks up the pixel-grid overlay. Reuses the tangent/normal
    /// stroking pattern from SpectrumEffect.buildCurveLine.
    private func appendTopOutline(points: [SIMD2<Float>], halfWidth: Float,
                                  to verts: inout [EffectVertex]) {
        guard points.count >= 2 else { return }
        let white = SIMD4<Float>(1, 1, 1, 1)
        for k in points.indices {
            var tangent = points[min(k + 1, points.count - 1)] - points[max(k - 1, 0)]
            let m = simd_length(tangent)
            tangent = m > 0 ? tangent / m : SIMD2(1, 0)
            let normal = SIMD2(-tangent.y, tangent.x) * halfWidth
            let a = EffectVertex(position: points[k] + normal, color: white, alpha: opacity, edgeDist: +1)
            let b = EffectVertex(position: points[k] - normal, color: white, alpha: opacity, edgeDist: -1)
            if k == 0, let lastV = verts.last {
                verts.append(lastV)
                verts.append(lastV)
                verts.append(a)
            }
            verts.append(a)
            verts.append(b)
        }
    }

    // MARK: - Color

    private func columnColor(x: Float, intensity: Float) -> SIMD4<Float> {
        let cs = waveformSettings.colorSettings
        switch cs.colorMode {
        case .rainbow:
            // Hue sweeps along the scroll axis so the history reads as a tail.
            let hue = 0.6 - x * 0.5
            return hsbToRGBA(h: hue, s: 0.8, b: 1.0, a: 1.0)
        case .gradient:
            let lo = SIMD4<Float>(Float(cs.gradientColorLow.red), Float(cs.gradientColorLow.green),
                                  Float(cs.gradientColorLow.blue), Float(cs.gradientColorLow.alpha))
            let hi = SIMD4<Float>(Float(cs.gradientColorHigh.red), Float(cs.gradientColorHigh.green),
                                  Float(cs.gradientColorHigh.blue), Float(cs.gradientColorHigh.alpha))
            return lo + (hi - lo) * min(intensity, 1)
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

extension WaveformEffect {
    static let descriptor = EffectDescriptor(
        type: .waveform,
        displayName: "Waveform",
        iconAssetName: "spectrum",   // TODO: dedicated icon; reusing spectrum's for now
        renderOrder: 12,
        makeDefaultSettings: { WaveformSettings.defaults },
        settingsCodec: .make(WaveformSettings.self),
        makeEffect: { size, layer, screen in
            WaveformEffect(size: size, layer: layer, screen: screen)
        },
        makeSettingsView: { AnyView(WaveformSettingsSection(layer: $0)) },
        pipelineSpec: PipelineSpec(
            vertexFunctionName: "spectrum_vertex",
            fragmentFunctionName: "spectrum_fragment",
            blendMode: .alphaBlend
        )
    )
}
