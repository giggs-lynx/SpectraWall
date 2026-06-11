//
//  SpectrumEffectDebug.swift
//  SpectraWall
//
//  Debug overlay for the spectrum bars. Draws each bar's rectangle outline
//  plus the anchor baseline and the maxHeight ceiling, all from the same
//  layout math as the rendered mesh (SpectrumEffect.makeLayout/barFrame) so
//  the wireframe cannot drift from the real bars.
//

import CoreGraphics
import Foundation
import simd

extension SpectrumEffect {

    private enum DebugColor {
        static let bar      = SIMD4<Float>(0, 1, 0, 1)   // green   per-bar outline
        static let baseline = SIMD4<Float>(0, 1, 1, 1)   // cyan    anchor baseline
        static let ceiling  = SIMD4<Float>(1, 0, 1, 1)   // magenta maxHeight ceiling
    }

    func buildSpectrumDebug(into canvas: inout DebugCanvas) {
        let layout = makeLayout()

        switch layout.style {
        case .bars:
            for i in 0..<binCount {
                drawBarRect(barFrame(i, in: layout), vertical: layout.vertical, into: &canvas)
            }
            if layout.caps {
                drawCapMarkers(layout, into: &canvas)
            }
        case .curve, .line:
            drawCurveSkeleton(layout, into: &canvas)
        }

        drawAmpAxisLine(at: layout.base, layout: layout,
                        color: DebugColor.baseline, into: &canvas)
        drawAmpAxisLine(at: layout.base + layout.tipSign * layout.maxExtent, layout: layout,
                        color: DebugColor.ceiling, into: &canvas)
        if layout.mirror {
            drawAmpAxisLine(at: layout.base - layout.tipSign * layout.maxExtent, layout: layout,
                            color: DebugColor.ceiling, into: &canvas)
        }
    }

    /// Cross-axis tick at every held cap position (reads current capLen
    /// without advancing it — the render pass owns the update).
    private func drawCapMarkers(_ layout: SpectrumLayout, into canvas: inout DebugCanvas) {
        for i in 0..<binCount where capLen[i] > 0 {
            let lo = layout.stripLo + CGFloat(i) * layout.stride
            let hi = lo + layout.barSize
            func tick(side: CGFloat) {
                let amp = layout.base + side * layout.tipSign * CGFloat(capLen[i])
                let a = layout.vertical ? CGPoint(x: lo, y: amp) : CGPoint(x: amp, y: lo)
                let b = layout.vertical ? CGPoint(x: hi, y: amp) : CGPoint(x: amp, y: hi)
                canvas.segment(a, b, color: DebugColor.ceiling, width: 1.5)
            }
            tick(side: 1)
            if layout.mirror { tick(side: -1) }
        }
    }

    /// Sampled tip spline (same sampler as the render mesh) plus a dot on
    /// every real control point so the 96 tips read apart from interpolation.
    private func drawCurveSkeleton(_ layout: SpectrumLayout, into canvas: inout DebugCanvas) {
        let samples = sampleCurve(in: layout)

        func pt(_ s: CurveSample, side: CGFloat) -> CGPoint {
            let amp = layout.base + side * layout.tipSign * CGFloat(s.len)
            return layout.vertical
                ? CGPoint(x: CGFloat(s.cross), y: amp)
                : CGPoint(x: amp, y: CGFloat(s.cross))
        }

        canvas.polyline(samples.map { pt($0, side: 1) }, color: DebugColor.bar, width: 1.5)
        if layout.mirror {
            canvas.polyline(samples.map { pt($0, side: -1) }, color: DebugColor.bar, width: 1.5)
        }
        for (k, s) in samples.enumerated() where k % curveSubdivisions == 0 {
            canvas.point(pt(s, side: 1), color: DebugColor.bar, size: 4)
        }
    }

    private func drawBarRect(_ f: BarFrame, vertical: Bool, into canvas: inout DebugCanvas) {
        let corners: [CGPoint]
        if vertical {
            corners = [CGPoint(x: CGFloat(f.lo), y: CGFloat(f.base)),
                       CGPoint(x: CGFloat(f.lo), y: CGFloat(f.tip)),
                       CGPoint(x: CGFloat(f.hi), y: CGFloat(f.tip)),
                       CGPoint(x: CGFloat(f.hi), y: CGFloat(f.base)),
                       CGPoint(x: CGFloat(f.lo), y: CGFloat(f.base))]
        } else {
            corners = [CGPoint(x: CGFloat(f.base), y: CGFloat(f.lo)),
                       CGPoint(x: CGFloat(f.tip), y: CGFloat(f.lo)),
                       CGPoint(x: CGFloat(f.tip), y: CGFloat(f.hi)),
                       CGPoint(x: CGFloat(f.base), y: CGFloat(f.hi)),
                       CGPoint(x: CGFloat(f.base), y: CGFloat(f.lo))]
        }
        canvas.polyline(corners, color: DebugColor.bar, width: 1.5)
    }

    /// Line at amplitude-axis coordinate `coord`, spanning the strip's full
    /// cross-axis extent.
    private func drawAmpAxisLine(at coord: CGFloat, layout: SpectrumLayout,
                                 color: SIMD4<Float>, into canvas: inout DebugCanvas) {
        let a, b: CGPoint
        if layout.vertical {
            a = CGPoint(x: layout.stripLo, y: coord)
            b = CGPoint(x: layout.stripHi, y: coord)
        } else {
            a = CGPoint(x: coord, y: layout.stripLo)
            b = CGPoint(x: coord, y: layout.stripHi)
        }
        canvas.segment(a, b, color: color, width: 1.5)
    }
}
