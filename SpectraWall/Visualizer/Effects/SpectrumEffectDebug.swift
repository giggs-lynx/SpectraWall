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

        for i in 0..<binCount {
            drawBarRect(barFrame(i, in: layout), vertical: layout.vertical, into: &canvas)
        }

        drawAmpAxisLine(at: layout.base, layout: layout,
                        color: DebugColor.baseline, into: &canvas)
        drawAmpAxisLine(at: layout.base + layout.tipSign * layout.maxExtent, layout: layout,
                        color: DebugColor.ceiling, into: &canvas)
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
