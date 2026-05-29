//
//  BorderEffectDebug.swift
//  SpectraWall
//
//  Debug overlay geometry for the border trail. Visualises the EXACT data
//  `appendBodyStrip` consumes — centerline + the two offset rails — so the
//  corner self-intersection is directly visible instead of inferred.
//
//  Both rails are analysed per segment: a rail segment that REVERSES relative to
//  the centerline (dot < 0) is a fold/bowtie; one that travels far further than
//  the centerline (length ratio high) is an overshoot/miter. Either way the strip
//  triangle that follows is degenerate — that's what fires the corner spike.
//  Failing segments are highlighted, and the worst sample is dumped to AppLog
//  once per settings change for hard numbers to drive the fix.
//

import CoreGraphics
import OSLog
import simd

/// Worst offending sample found while scanning the rails, for the numeric dump.
private struct BorderDebugWorst {
    var ratio: CGFloat
    var sample: Int
    var stroke: Int
    var center: CGPoint
    var railA: CGPoint
    var railB: CGPoint
    var halfW: CGFloat
}

extension BorderEffect {

    private enum DebugColor {
        static let centerline = SIMD4<Float>(0, 1, 0, 1)   // green
        static let railA      = SIMD4<Float>(0, 1, 1, 1)   // cyan  (point + normal·halfW)
        static let railB      = SIMD4<Float>(1, 0, 0, 1)   // red   (point − normal·halfW)
        static let fold       = SIMD4<Float>(1, 1, 0, 1)   // yellow  (rail reverses)
        static let overshoot  = SIMD4<Float>(1, 0, 1, 1)   // magenta (rail travels far)
    }

    /// A rail segment whose length exceeds this multiple of the centerline
    /// segment is flagged as an overshoot (miter-style shoot-out).
    private static let overshootRatio: CGFloat = 4

    func buildBorderDebug(into canvas: inout DebugCanvas) {
        var worst: BorderDebugWorst?
        var foldCount = 0

        for strokeIndex in 0..<strokes.count {
            // Same args as buildEffectMesh → rails are byte-for-byte what
            // appendBodyStrip emits.
            let ctx = prepareEffectMesh(
                progress: strokes[strokeIndex].progress,
                amplitude: amplitude(forStroke: strokeIndex),
                stripScale: 1.0,
                strokeIndex: strokeIndex,
                alpha: nil
            )
            let n = ctx.centerPoints.count
            guard n >= 2 else { continue }

            var center: [CGPoint] = []
            var railA: [CGPoint] = []
            var railB: [CGPoint] = []
            var halfWidths: [CGFloat] = []
            center.reserveCapacity(n); railA.reserveCapacity(n)
            railB.reserveCapacity(n); halfWidths.reserveCapacity(n)
            for i in 0..<n {
                let p = ctx.centerPoints[i]
                let normal = perp(ctx.tangents[i])
                let halfW = ctx.stripWidths[i] / 2
                // Reconstruct the SAME clamped rails appendBodyStrip now emits,
                // so the fold/overshoot detector verifies the fix (not stale
                // unclamped geometry).
                let (radius, innerIsPlusN) = localCurvature(ctx.centerPoints, at: i)
                let off = clampedRailOffsets(halfW: halfW, radius: radius, innerIsPlusN: innerIsPlusN)
                center.append(p)
                railA.append(CGPoint(x: p.x + normal.x * off.hA, y: p.y + normal.y * off.hA))
                railB.append(CGPoint(x: p.x - normal.x * off.hB, y: p.y - normal.y * off.hB))
                halfWidths.append(halfW)
            }

            canvas.polyline(center, color: DebugColor.centerline, width: 1.5)
            canvas.polyline(railA, color: DebugColor.railA, width: 1.5)
            canvas.polyline(railB, color: DebugColor.railB, width: 1.5)

            // Highlight failing segments on BOTH rails, and track the worst.
            for rail in [railA, railB] {
                for i in 0..<(n - 1) {
                    let cs = CGPoint(x: center[i + 1].x - center[i].x,
                                     y: center[i + 1].y - center[i].y)
                    let rs = CGPoint(x: rail[i + 1].x - rail[i].x,
                                     y: rail[i + 1].y - rail[i].y)
                    let csLen = (cs.x * cs.x + cs.y * cs.y).squareRoot()
                    let rsLen = (rs.x * rs.x + rs.y * rs.y).squareRoot()
                    let dot = rs.x * cs.x + rs.y * cs.y
                    let ratio = csLen > 0 ? rsLen / csLen : .infinity

                    if dot < 0 {
                        canvas.segment(rail[i], rail[i + 1], color: DebugColor.fold, width: 4)
                        canvas.point(rail[i], color: DebugColor.fold, size: 8)
                        foldCount += 1
                    } else if ratio > Self.overshootRatio {
                        canvas.segment(rail[i], rail[i + 1], color: DebugColor.overshoot, width: 4)
                    }

                    if worst == nil || ratio > worst!.ratio {
                        worst = BorderDebugWorst(ratio: ratio, sample: i, stroke: strokeIndex,
                                                 center: center[i], railA: railA[i],
                                                 railB: railB[i], halfW: halfWidths[i])
                    }
                }
            }
        }

        dumpOnce(worst: worst, foldCount: foldCount)
    }

    private func dumpOnce(worst: BorderDebugWorst?, foldCount: Int) {
        // Wait for a frame that actually exhibits the spike (trail over a
        // corner) so the dump captures the patient, not a straight section.
        guard !debugDumped, let w = worst,
              foldCount > 0 || w.ratio > Self.overshootRatio else { return }
        debugDumped = true
        let bs = borderSettings
        let inset = CGFloat(bs.baseWidth) / 2
        let effectiveR = max(CGFloat(bs.cornerRadius) - inset, 0)
        AppLog.effect.info("""
            [border-debug] baseWidth=\(bs.baseWidth, privacy: .public) \
            cornerRadius=\(bs.cornerRadius, privacy: .public) \
            inset=\(Double(inset), privacy: .public) effectiveCornerR=\(Double(effectiveR), privacy: .public)
            [border-debug] worst stroke=\(w.stroke, privacy: .public) sample=\(w.sample, privacy: .public) \
            railSeg/centerSeg=\(Double(w.ratio), privacy: .public)x halfW=\(Double(w.halfW), privacy: .public) \
            foldSegments=\(foldCount, privacy: .public)
            [border-debug] center=(\(Double(w.center.x), privacy: .public),\(Double(w.center.y), privacy: .public)) \
            railA=(\(Double(w.railA.x), privacy: .public),\(Double(w.railA.y), privacy: .public)) \
            railB=(\(Double(w.railB.x), privacy: .public),\(Double(w.railB.y), privacy: .public))
            """)
    }
}
