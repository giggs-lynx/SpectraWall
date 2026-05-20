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
    /// One segment of the rounded-rectangle border path. Straight edges are `.line`;
    /// rounded corners are `.bezier` (quintic — degree 5), which gives C2 continuity at
    /// the line↔corner boundary (curvature = 0 at both endpoints) and eliminates the
    /// visible "breakpoint" a thick stroke shows where a line meets a circular arc.
    struct BorderSegment {
        enum Kind {
            case line(start: CGPoint, end: CGPoint)
            /// `controls` is 6 control points P0…P5. `arcLUT` has 33 entries of cumulative
            /// chord length sampled at uniform `t∈[0,1]`. `arcLUT.last == length`.
            case bezier(controls: [CGPoint], arcLUT: [CGFloat])
        }

        var kind: Kind
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

        /// Build the 33-entry arc-length LUT for a quintic Bézier and return
        /// (lut, totalLength, minRadius). Sampling at 32 segments gives ~0.05% length error.
        static func buildBezierTables(_ controls: [CGPoint]) -> (lut: [CGFloat], length: CGFloat, minRadius: CGFloat) {
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
                lut.append(lut.last! + sqrt(dx * dx + dy * dy))
                prevPoint = p

                let k = abs(curvature(controls, t: t))
                if k > maxKappa { maxKappa = k }
            }
            let minRadius: CGFloat = maxKappa > 0 ? 1 / maxKappa : .infinity
            return (lut, lut.last!, minRadius)
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
    
    func interpolateNSColor(from startColor: NSColor, to endColor: NSColor, progress: CGFloat) -> NSColor {
        NSColor(
            red: startColor.redComponent + (endColor.redComponent - startColor.redComponent) * progress,
            green: startColor.greenComponent + (endColor.greenComponent - startColor.greenComponent) * progress,
            blue: startColor.blueComponent + (endColor.blueComponent - startColor.blueComponent) * progress,
            alpha: 1.0
        )
    }
    
    func interpolateColor(from startColor: NSColor, to endColor: NSColor, progress: CGFloat) -> NSColor {
        interpolateNSColor(from: startColor, to: endColor, progress: progress)
    }
    
    func boundingCenter(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 0
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
    
    func makeRelativePath(points: [CGPoint], center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x - center.x, y: first.y - center.y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x - center.x, y: point.y - center.y))
        }
        return path
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
        let tRight = CGPoint(x:  1, y:  0)
        let tDown  = CGPoint(x:  0, y:  1)
        let tLeft  = CGPoint(x: -1, y:  0)
        let tUp    = CGPoint(x:  0, y: -1)

        let segs: [BorderSegment] = [
            // Top edge
            makeLine(CGPoint(x: inset + r,         y: inset),
                     CGPoint(x: inset + width - r, y: inset)),
            // Top-right corner
            makeBezierCorner(start: CGPoint(x: inset + width - r, y: inset),
                             end:   CGPoint(x: inset + width,     y: inset + r),
                             t0: tRight, t1: tDown, r: r),
            // Right edge
            makeLine(CGPoint(x: inset + width, y: inset + r),
                     CGPoint(x: inset + width, y: inset + height - r)),
            // Bottom-right corner
            makeBezierCorner(start: CGPoint(x: inset + width,     y: inset + height - r),
                             end:   CGPoint(x: inset + width - r, y: inset + height),
                             t0: tDown, t1: tLeft, r: r),
            // Bottom edge
            makeLine(CGPoint(x: inset + width - r, y: inset + height),
                     CGPoint(x: inset + r,         y: inset + height)),
            // Bottom-left corner
            makeBezierCorner(start: CGPoint(x: inset + r, y: inset + height),
                             end:   CGPoint(x: inset,     y: inset + height - r),
                             t0: tLeft, t1: tUp, r: r),
            // Left edge
            makeLine(CGPoint(x: inset, y: inset + height - r),
                     CGPoint(x: inset, y: inset + r)),
            // Top-left corner
            makeBezierCorner(start: CGPoint(x: inset,     y: inset + r),
                             end:   CGPoint(x: inset + r, y: inset),
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
        let (lut, length, minRadius) = BorderSegment.buildBezierTables(controls)
        return BorderSegment(kind: .bezier(controls: controls, arcLUT: lut),
                             length: length,
                             minRadius: minRadius)
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

// MARK: - Trail Vertex Building

extension BorderEffect {
    
    func buildStripFromCenterline(
        points: [CGPoint],
        width: CGFloat,
        color: SIMD4<Float>,
        alpha: Float
    ) -> [TrailVertex] {
        var vertices: [TrailVertex] = []
        let half = width / 2
        for index in 0..<points.count {
            let point = points[index]
            let normal: CGPoint
            if index == 0 {
                normal = perp(normalize(CGPoint(x: points[1].x - point.x, y: points[1].y - point.y)))
            } else if index == points.count - 1 {
                let prev = points[index - 1]
                normal = perp(normalize(CGPoint(x: point.x - prev.x, y: point.y - prev.y)))
            } else {
                let prev = points[index - 1]
                let next = points[index + 1]
                normal = perp(normalize(CGPoint(x: next.x - prev.x, y: next.y - prev.y)))
            }
            vertices.append(TrailVertex(
                position: SIMD2(Float(point.x + normal.x * half), Float(point.y + normal.y * half)),
                color: color, alpha: alpha, edgeDist: -1.0
            ))
            vertices.append(TrailVertex(
                position: SIMD2(Float(point.x - normal.x * half), Float(point.y - normal.y * half)),
                color: color, alpha: alpha, edgeDist: 1.0
            ))
        }
        return vertices
    }
    
    private struct TrailContext {
        var centerPoints: [CGPoint] = []
        var widths: [CGFloat] = []
        var stripWidths: [CGFloat] = []
        var colors: [SIMD4<Float>] = []      // pre-converted; avoids per-step NSColor alloc
        var alphas: [CGFloat] = []
        var tangents: [CGPoint] = []         // unit forward tangent in ctx iteration order (y-flipped)
    }

    private func prepareTrailData(
        progress: Double,
        amplitude: Float,
        stripScale: CGFloat,
        strokeIndex: Int,
        alpha: Float?
    ) -> TrailContext {
        let bs = borderSettings
        let segments = borderSegments()
        let inset = max(CGFloat(bs.baseWidth) / 2, 0)
        // Sample density still scales with the corner-curve length so corners get enough
        // samples regardless of trail length. cornerRadius - inset is the Bézier corner's
        // approximate span; use it as the density anchor (same role as the old arcLength).
        let cornerSpan = max(CGFloat(bs.cornerRadius) - inset, 0)
        let trailLength = CGFloat(bs.tailLength) * perimeterLength
        let steps: Int = {
            guard cornerSpan > 0 else { return 120 }
            let needed = Int(trailLength / cornerSpan) * 8
            return max(120, min(needed, 1200))
        }()
        let capacity = steps + 1

        // Convert palette colors once — reused for every step via SIMD lerp.
        let startNS  = strokeIndex == 0 ? bs.stroke1ColorStart.nsColor : bs.stroke2ColorStart.nsColor
        let endNS    = strokeIndex == 0 ? bs.stroke1ColorEnd.nsColor   : bs.stroke2ColorEnd.nsColor
        let colorStartV = SIMD4<Float>(Float(startNS.redComponent), Float(startNS.greenComponent),
                                       Float(startNS.blueComponent), 1.0)
        let colorEndV   = SIMD4<Float>(Float(endNS.redComponent),   Float(endNS.greenComponent),
                                       Float(endNS.blueComponent),   1.0)

        var ctx = TrailContext()
        ctx.centerPoints.reserveCapacity(capacity)
        ctx.widths.reserveCapacity(capacity)
        ctx.stripWidths.reserveCapacity(capacity)
        ctx.colors.reserveCapacity(capacity)
        ctx.alphas.reserveCapacity(capacity)
        ctx.tangents.reserveCapacity(capacity)

        let heightF = sceneSize.height

        for stepIndex in 0...steps {
            let stepT  = CGFloat(stepIndex) / CGFloat(steps)
            let stepTF = Float(stepT)
            let distAlong = stepT * CGFloat(bs.tailLength) * perimeterLength
            let rawDist = CGFloat(progress) * perimeterLength + (bs.clockwise ? distAlong : -distAlong)
            let wrapped = ((rawDist.truncatingRemainder(dividingBy: perimeterLength)) + perimeterLength)
                .truncatingRemainder(dividingBy: perimeterLength)

            let (segIdx, localDist) = segmentAt(distance: wrapped, segments: segments)
            let seg = segments[segIdx]
            let localT = seg.length > 0 ? min(localDist / seg.length, 1.0) : 0
            let (point, tangent) = seg.sample(at: localT)

            let baseW = (CGFloat(bs.baseWidth) + CGFloat(amplitude) * 3.0) * stepT
            // Fold y-flip into the append to avoid a separate map pass after the loop.
            ctx.centerPoints.append(CGPoint(x: point.x, y: heightF - point.y))
            ctx.widths.append(baseW)
            ctx.stripWidths.append(baseW * 3.0 * stripScale)
            ctx.colors.append(colorEndV + (colorStartV - colorEndV) * stepTF)
            ctx.alphas.append(alpha != nil ? CGFloat(alpha ?? 0) : stepT)
            // Y-flip the tangent's y component to match centerPoints coordinate space.
            ctx.tangents.append(CGPoint(x: tangent.x, y: -tangent.y))
        }

        ctx.centerPoints.reverse()
        ctx.widths.reverse()
        ctx.stripWidths.reverse()
        ctx.colors.reverse()
        ctx.alphas.reverse()
        ctx.tangents.reverse()
        // After the reverse, ctx[i+1] is "earlier on the path" than ctx[i]. We want
        // tangents to point in the iteration order (toward ctx[i+1]), so negate.
        for i in 0..<ctx.tangents.count {
            ctx.tangents[i] = CGPoint(x: -ctx.tangents[i].x, y: -ctx.tangents[i].y)
        }
        return ctx
    }

    private func appendHeadFan(ctx: TrailContext, to vertices: inout [TrailVertex]) {
        let hCenter = ctx.centerPoints[0]
        let hDir = normalize(CGPoint(x: hCenter.x - ctx.centerPoints[1].x, y: hCenter.y - ctx.centerPoints[1].y))
        let hNormal = perp(hDir)
        let hRadius = ctx.widths[0] / 2
        let hColor  = ctx.colors[0]
        let hAlpha  = Float(ctx.alphas[0])
        let fanSteps = 16
        
        for fanIndex in 0...fanSteps {
            let angle = CGFloat(fanIndex) / CGFloat(fanSteps) * .pi
            let ox = hNormal.x * cos(angle) * hRadius + hDir.x * sin(angle) * hRadius
            let oy = hNormal.y * cos(angle) * hRadius + hDir.y * sin(angle) * hRadius
            vertices.append(TrailVertex(position: SIMD2<Float>(Float(hCenter.x), Float(hCenter.y)),
                                        color: hColor, alpha: hAlpha, edgeDist: 0.0))
            vertices.append(TrailVertex(position: SIMD2<Float>(Float(hCenter.x + ox), Float(hCenter.y + oy)),
                                        color: hColor, alpha: hAlpha, edgeDist: 1.0))
        }
        
        if let lastFan = vertices.last {
            let firstNormal = perp(normalize(CGPoint(x: ctx.centerPoints[1].x - hCenter.x,
                                                     y: ctx.centerPoints[1].y - hCenter.y)))
            let halfW = ctx.stripWidths[0] / 2
            vertices.append(lastFan)
            vertices.append(lastFan)
            vertices.append(TrailVertex(position: SIMD2<Float>(Float(hCenter.x + firstNormal.x * halfW),
                                                               Float(hCenter.y + firstNormal.y * halfW)),
                                        color: hColor, alpha: hAlpha, edgeDist: -1.0))
        }
    }
    
    private func appendBodyStrip(ctx: TrailContext, to vertices: inout [TrailVertex]) {
        let steps = ctx.centerPoints.count - 1
        for i in 0...steps {
            let point = ctx.centerPoints[i]
            // Unified normal: perpendicular of the analytic tangent from seg.sample(at:).
            // No line-vs-curve branch — straight edges and Bézier corners use the same code
            // path, which is the whole point of moving to a single curve representation.
            let normal = perp(ctx.tangents[i])
            let halfW  = ctx.stripWidths[i] / 2
            let innerHalfW = halfW

            let color4 = ctx.colors[i]
            let alpha  = Float(ctx.alphas[i])
            vertices.append(TrailVertex(position: SIMD2<Float>(Float(point.x + normal.x * halfW),
                                                               Float(point.y + normal.y * halfW)),
                                        color: color4, alpha: alpha, edgeDist: -1.0))
            vertices.append(TrailVertex(position: SIMD2<Float>(Float(point.x - normal.x * innerHalfW),
                                                               Float(point.y - normal.y * innerHalfW)),
                                        color: color4, alpha: alpha, edgeDist: 1.0))
        }
    }
    
    func buildTrailVertices(
        strokeIndex: Int,
        progress: Double,
        amplitude: Float,
        stripScale: CGFloat,
        alpha: Float?
    ) -> [TrailVertex] {
        let ctx = prepareTrailData(progress: progress, amplitude: amplitude, stripScale: stripScale,
                                   strokeIndex: strokeIndex, alpha: alpha)
        var vertices: [TrailVertex] = []
        vertices.reserveCapacity(ctx.centerPoints.count * 2 + 40)
        appendHeadFan(ctx: ctx, to: &vertices)
        appendBodyStrip(ctx: ctx, to: &vertices)
        return vertices
    }
    
    func buildTrailData(strokeIndex: Int) -> TrailData {
        let amplitude: Float = strokes.count == 1
        ? (smoothedLeft + smoothedRight) / 2
        : (strokeIndex == 0 ? smoothedLeft : smoothedRight)
        let vertices = buildTrailVertices(
            strokeIndex: strokeIndex,
            progress: strokes[strokeIndex].progress,
            amplitude: amplitude,
            stripScale: 1.0,
            alpha: nil
        )
        return TrailData(vertices: vertices)
    }
    
    func buildGhostTrailData(
        strokeIndex: Int,
        progressOffset: Double,
        amplitude: Float,
        scale: CGFloat,
        alpha: Float
    ) -> TrailData {
        let progress = (strokes[strokeIndex].progress + progressOffset)
            .truncatingRemainder(dividingBy: 1.0)
        var vertices = buildTrailVertices(
            strokeIndex: strokeIndex,
            progress: progress,
            amplitude: amplitude,
            stripScale: 1.0,
            alpha: alpha
        )
        
        // Scale outward from the screen center, in-place to avoid a second array copy.
        let screenCenter = SIMD2<Float>(Float(sceneSize.width / 2), Float(sceneSize.height / 2))
        let scaleF = Float(scale)
        for i in 0..<vertices.count {
            vertices[i].position = screenCenter + (vertices[i].position - screenCenter) * scaleF
        }

        return TrailData(vertices: vertices)
    }
}
