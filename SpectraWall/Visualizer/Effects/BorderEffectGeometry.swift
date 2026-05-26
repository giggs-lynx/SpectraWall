//
//  BorderEffectGeometry.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/2.
//

import CoreGraphics
import AppKit
import simd

// MARK: - BorderSegment

extension BorderEffect {
    struct BezierTableResult {
        var lut: [CGFloat]
        var length: CGFloat
        var minRadius: CGFloat
    }

    enum BorderSegmentKind {
        case line(start: CGPoint, end: CGPoint)
        case bezier(controls: [CGPoint], arcLUT: [CGFloat])
    }

    struct BorderSegment {

        var kind: BorderSegmentKind
        var length: CGFloat
        /// Smallest radius of curvature along the segment (= 1 / max |κ|). For lines this
        /// is `.infinity`; for the corner Bézier it's the tightest local radius (occurs
        /// somewhere in the middle of the curve). Drives the corner-narrow cap clamp.
        var minRadius: CGFloat

        /// Returns position + unit tangent (direction of increasing t) at `localT ∈ [0,1]`.
        /// `localT` is interpreted by **arc length**, not curve parameter, so trail samples
        /// are uniformly spaced along the visible path.
        func sample(at localT: CGFloat) -> (point: CGPoint, tangent: CGPoint) {
            switch kind {
            case .line(let start, let end):
                let dx = end.x - start.x
                let dy = end.y - start.y
                let len = sqrt(dx * dx + dy * dy)
                let tangent: CGPoint = len > 0
                    ? CGPoint(x: dx / len, y: dy / len)
                    : CGPoint(x: 1, y: 0)
                let pt = CGPoint(x: start.x + dx * localT, y: start.y + dy * localT)
                return (pt, tangent)

            case .bezier(let controls, let arcLUT):
                guard length > 0 else {
                    return (controls[0], CGPoint(x: 1, y: 0))
                }
                let t = Self.parameterForArcLength(localT * length, lut: arcLUT)
                let pt = Self.evaluateQuintic(controls, t: t)
                let tan = Self.evaluateQuinticTangent(controls, t: t)
                return (pt, tan)
            }
        }

        // MARK: - Quintic Bézier evaluation helpers

        /// de Casteljau on 6 control points → point at parameter t.
        static func evaluateQuintic(_ controls: [CGPoint], t: CGFloat) -> CGPoint {
            var pts = controls
            for level in (1...5).reversed() {
                for i in 0..<level {
                    pts[i] = CGPoint(
                        x: pts[i].x + (pts[i + 1].x - pts[i].x) * t,
                        y: pts[i].y + (pts[i + 1].y - pts[i].y) * t
                    )
                }
            }
            return pts[0]
        }

        /// Unit tangent at parameter t. The derivative B'(t) of a degree-5 Bézier is a
        /// degree-4 Bézier whose control points are `Q_i = 5·(P_{i+1} − P_i)`.
        static func evaluateQuinticTangent(_ controls: [CGPoint], t: CGFloat) -> CGPoint {
            var pts: [CGPoint] = (0..<5).map { i in
                CGPoint(
                    x: 5 * (controls[i + 1].x - controls[i].x),
                    y: 5 * (controls[i + 1].y - controls[i].y)
                )
            }
            for level in (1...4).reversed() {
                for i in 0..<level {
                    pts[i] = CGPoint(
                        x: pts[i].x + (pts[i + 1].x - pts[i].x) * t,
                        y: pts[i].y + (pts[i + 1].y - pts[i].y) * t
                    )
                }
            }
            let len = sqrt(pts[0].x * pts[0].x + pts[0].y * pts[0].y)
            return len > 0 ? CGPoint(x: pts[0].x / len, y: pts[0].y / len) : CGPoint(x: 1, y: 0)
        }

        static func buildBezierTables(_ controls: [CGPoint]) -> BezierTableResult {
            let steps = 32
            var lut: [CGFloat] = []
            lut.reserveCapacity(steps + 1)
            lut.append(0)
            var prevPoint = controls[0]
            var maxKappa: CGFloat = 0

            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let p = evaluateQuintic(controls, t: t)
                let dx = p.x - prevPoint.x
                let dy = p.y - prevPoint.y
                let prevLen = lut[lut.count - 1]
                lut.append(prevLen + sqrt(dx * dx + dy * dy))
                prevPoint = p

                let k = abs(curvature(controls, t: t))
                if k > maxKappa { maxKappa = k }
            }
            let totalLength = lut[lut.count - 1]
            let minRadius: CGFloat = maxKappa > 0 ? 1 / maxKappa : .infinity
            return BezierTableResult(lut: lut, length: totalLength, minRadius: minRadius)
        }

        /// Signed curvature κ(t) = (x'·y'' − y'·x'') / (x'² + y'²)^(3/2).
        /// Used only at LUT build time, not per-frame.
        private static func curvature(_ controls: [CGPoint], t: CGFloat) -> CGFloat {
            // B'(t): degree-4 Bézier of Q_i = 5·(P_{i+1} − P_i)
            var qs: [CGPoint] = (0..<5).map { i in
                CGPoint(
                    x: 5 * (controls[i + 1].x - controls[i].x),
                    y: 5 * (controls[i + 1].y - controls[i].y)
                )
            }
            // B''(t): degree-3 Bézier of R_i = 4·(Q_{i+1} − Q_i)
            var rs: [CGPoint] = (0..<4).map { i in
                CGPoint(
                    x: 4 * (qs[i + 1].x - qs[i].x),
                    y: 4 * (qs[i + 1].y - qs[i].y)
                )
            }
            // Evaluate both at t via de Casteljau.
            for level in (1...4).reversed() {
                for i in 0..<level {
                    qs[i] = CGPoint(
                        x: qs[i].x + (qs[i + 1].x - qs[i].x) * t,
                        y: qs[i].y + (qs[i + 1].y - qs[i].y) * t
                    )
                }
            }
            for level in (1...3).reversed() {
                for i in 0..<level {
                    rs[i] = CGPoint(
                        x: rs[i].x + (rs[i + 1].x - rs[i].x) * t,
                        y: rs[i].y + (rs[i + 1].y - rs[i].y) * t
                    )
                }
            }
            let bp = qs[0], bpp = rs[0]
            let denom = pow(bp.x * bp.x + bp.y * bp.y, 1.5)
            guard denom > 0 else { return 0 }
            return (bp.x * bpp.y - bp.y * bpp.x) / denom
        }

        /// Invert the cumulative arc-length LUT: given a target arc length `s`,
        /// return the curve parameter `t ∈ [0,1]` whose arc length equals `s`.
        /// Binary search + linear interp between LUT entries.
        private static func parameterForArcLength(_ s: CGFloat, lut: [CGFloat]) -> CGFloat {
            let total = lut.last ?? 0
            if total <= 0 || s <= 0 { return 0 }
            if s >= total { return 1 }
            var lo = 0
            var hi = lut.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if lut[mid] <= s { lo = mid } else { hi = mid }
            }
            let span = lut[hi] - lut[lo]
            let f = span > 0 ? (s - lut[lo]) / span : 0
            return (CGFloat(lo) + f) / CGFloat(lut.count - 1)
        }
    }
}

// MARK: - Geometry Helpers

extension BorderEffect {
    
    func normalize(_ vector: CGPoint) -> CGPoint {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y)
        guard length > 0 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }
    
    func perp(_ vector: CGPoint) -> CGPoint {
        CGPoint(x: -vector.y, y: vector.x)
    }
}

// MARK: - Border Segments & Path

extension BorderEffect {
    
    func borderSegments() -> [BorderSegment] {
        let bs = borderSettings
        let inset = max(CGFloat(bs.baseWidth) / 2, 0)

        if let cache = segmentCache,
           cachedSceneSize == sceneSize,
           cachedCornerRadius == bs.cornerRadius {
            return cache
        }

        let width  = max(0, sceneSize.width - inset * 2)
        let height = max(0, sceneSize.height - inset * 2)
        let r      = max(CGFloat(bs.cornerRadius) - inset, 0)

        // CW around the screen: top → right → bottom → left.
        // Each rounded corner is a quintic Bézier whose endpoints are tangent to the
        // adjoining straight edges AND have zero curvature there — eliminates the
        // line→arc C2 jump that shows up as a visible "kink" on thick strokes.
        let tRight = CGPoint(x: 1, y: 0)
        let tDown = CGPoint(x: 0, y: 1)
        let tLeft = CGPoint(x: -1, y: 0)
        let tUp = CGPoint(x: 0, y: -1)

        let segs: [BorderSegment] = [
            makeLine(CGPoint(x: inset + r, y: inset),
                     CGPoint(x: inset + width - r, y: inset)),
            makeBezierCorner(start: CGPoint(x: inset + width - r, y: inset),
                             end: CGPoint(x: inset + width, y: inset + r),
                             t0: tRight, t1: tDown, r: r),
            makeLine(CGPoint(x: inset + width, y: inset + r),
                     CGPoint(x: inset + width, y: inset + height - r)),
            makeBezierCorner(start: CGPoint(x: inset + width, y: inset + height - r),
                             end: CGPoint(x: inset + width - r, y: inset + height),
                             t0: tDown, t1: tLeft, r: r),
            makeLine(CGPoint(x: inset + width - r, y: inset + height),
                     CGPoint(x: inset + r, y: inset + height)),
            makeBezierCorner(start: CGPoint(x: inset + r, y: inset + height),
                             end: CGPoint(x: inset, y: inset + height - r),
                             t0: tLeft, t1: tUp, r: r),
            makeLine(CGPoint(x: inset, y: inset + height - r),
                     CGPoint(x: inset, y: inset + r)),
            makeBezierCorner(start: CGPoint(x: inset, y: inset + r),
                             end: CGPoint(x: inset + r, y: inset),
                             t0: tUp, t1: tRight, r: r)
        ]

        segmentCache = segs
        cachedSceneSize = sceneSize
        cachedCornerRadius = bs.cornerRadius
        return segs
    }

    private func makeLine(_ start: CGPoint, _ end: CGPoint) -> BorderSegment {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return BorderSegment(kind: .line(start: start, end: end),
                             length: sqrt(dx * dx + dy * dy),
                             minRadius: .infinity)
    }

    /// Construct a quintic Bézier corner. P0, P5 fixed at `start`/`end`.
    /// `t0`, `t1` are the unit tangents (incoming / outgoing line directions).
    /// P0–P1–P2 colinear along `t0` and P3–P4–P5 colinear along `t1` ⇒ κ = 0 at both
    /// endpoints (matching the adjoining straight edges' zero curvature).
    /// Handle constants 0.30 / 0.35 chosen to approximate a quarter-circle footprint.
    private func makeBezierCorner(start: CGPoint, end: CGPoint,
                                  t0: CGPoint, t1: CGPoint, r: CGFloat) -> BorderSegment {
        let a = r * 0.30
        let b = r * 0.35
        let p1 = CGPoint(x: start.x + a * t0.x, y: start.y + a * t0.y)
        let p2 = CGPoint(x: p1.x    + b * t0.x, y: p1.y    + b * t0.y)
        let p4 = CGPoint(x: end.x   - a * t1.x, y: end.y   - a * t1.y)
        let p3 = CGPoint(x: p4.x    - b * t1.x, y: p4.y    - b * t1.y)
        let controls = [start, p1, p2, p3, p4, end]
        let tables = BorderSegment.buildBezierTables(controls)
        return BorderSegment(kind: .bezier(controls: controls, arcLUT: tables.lut),
                             length: tables.length,
                             minRadius: tables.minRadius)
    }
    
    func segmentAt(distance: CGFloat, segments: [BorderSegment]) -> (Int, CGFloat) {
        var accumulated: CGFloat = 0
        for (index, seg) in segments.enumerated() {
            if accumulated + seg.length > distance {
                return (index, distance - accumulated)
            }
            accumulated += seg.length
        }
        return (segments.count - 1, segments.last?.length ?? 0)
    }
    
    func borderPath(from progress: Double, length: CGFloat, clockwise: Bool) -> CGPath {
        let path = CGMutablePath()
        let segments = borderSegments()
        guard perimeterLength > 0, length > 0 else { return path }
        
        let steps = 120
        var isStarted = false
        
        for stepIndex in 0...steps {
            let stepT = CGFloat(stepIndex) / CGFloat(steps)
            let distAlongTrail = stepT * length
            let rawDist = CGFloat(progress) * perimeterLength + (clockwise ? distAlongTrail : -distAlongTrail)
            let wrapped = ((rawDist.truncatingRemainder(dividingBy: perimeterLength)) + perimeterLength)
                .truncatingRemainder(dividingBy: perimeterLength)
            
            let (segIdx, localDist) = segmentAt(distance: wrapped, segments: segments)
            let seg = segments[segIdx]
            let localT = seg.length > 0 ? min(localDist / seg.length, 1.0) : 0
            let point = seg.sample(at: localT).point

            if !isStarted {
                path.move(to: point)
                isStarted = true
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
    
    func collectTailPoints(strokeIndex: Int, tailLength: Double, clockwise: Bool) -> [CGPoint] {
        let segments = borderSegments()
        guard perimeterLength > 0, !segments.isEmpty else { return [] }
        
        let resolution = 60
        let tailDist = perimeterLength * CGFloat(tailLength)
        let headDist = CGFloat(strokes[strokeIndex].progress) * perimeterLength
        
        let startDist: CGFloat
        if clockwise {
            startDist = ((headDist - tailDist)
                .truncatingRemainder(dividingBy: perimeterLength) + perimeterLength)
            .truncatingRemainder(dividingBy: perimeterLength)
        } else {
            startDist = headDist
        }
        
        var points: [CGPoint] = []
        points.reserveCapacity(resolution)
        
        for stepIndex in 0..<resolution {
            let stepT = CGFloat(stepIndex) / CGFloat(resolution - 1)
            let dist: CGFloat
            if clockwise {
                dist = (startDist + stepT * tailDist)
                    .truncatingRemainder(dividingBy: perimeterLength)
            } else {
                dist = ((startDist - stepT * tailDist)
                    .truncatingRemainder(dividingBy: perimeterLength) + perimeterLength)
                .truncatingRemainder(dividingBy: perimeterLength)
            }
            
            let (segIdx, localDist) = segmentAt(distance: dist, segments: segments)
            let seg = segments[segIdx]
            let localT = seg.length > 0 ? localDist / seg.length : 0
            points.append(seg.sample(at: localT).point)
        }

        return points
    }
}
