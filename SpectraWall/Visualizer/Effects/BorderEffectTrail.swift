//
//  BorderEffectTrail.swift
//  SpectraWall
//

import CoreGraphics
import AppKit
import simd

// MARK: - Trail Vertex Building

/// Per-sample rail offsets + their edgeDist, after corner clamping.
struct RailOffsets {
    var hA: CGFloat
    var hB: CGFloat
    var edgeA: Float
    var edgeB: Float
}

extension BorderEffect {

    func buildStripFromCenterline(
        points: [CGPoint],
        width: CGFloat,
        color: SIMD4<Float>,
        alpha: Float
    ) -> [EffectVertex] {
        var vertices: [EffectVertex] = []
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
            vertices.append(EffectVertex(
                position: SIMD2(Float(point.x + normal.x * half), Float(point.y + normal.y * half)),
                color: color, alpha: alpha, edgeDist: -1.0
            ))
            vertices.append(EffectVertex(
                position: SIMD2(Float(point.x - normal.x * half), Float(point.y - normal.y * half)),
                color: color, alpha: alpha, edgeDist: 1.0
            ))
        }
        return vertices
    }

    struct TrailContext {
        var centerPoints: [CGPoint] = []
        var widths: [CGFloat] = []
        var stripWidths: [CGFloat] = []
        var colors: [SIMD4<Float>] = []
        var alphas: [CGFloat] = []
        var tangents: [CGPoint] = []

        mutating func reverseAndFlipTangents() {
            centerPoints.reverse()
            widths.reverse()
            stripWidths.reverse()
            colors.reverse()
            alphas.reverse()
            tangents.reverse()
            for i in 0..<tangents.count {
                tangents[i] = CGPoint(x: -tangents[i].x, y: -tangents[i].y)
            }
        }
    }

    func prepareEffectMesh(
        progress: Double,
        amplitude: Float,
        stripScale: CGFloat,
        strokeIndex: Int,
        alpha: Float?,
        tailLengthOverride: Double? = nil
    ) -> TrailContext {
        let bs = borderSettings
        let segments = borderSegments()
        let inset = max(CGFloat(bs.baseWidth) / 2, 0)
        let cornerSpan = max(CGFloat(bs.cornerRadius) - inset, 0)
        let effectiveTailLength = CGFloat(tailLengthOverride ?? Double(bs.tailLength))
        let trailLength = effectiveTailLength * perimeterLength
        let steps: Int = {
            // Sample finely enough that tight corners (small effective radius)
            // don't facet/miter on the outer rail. cornerSpan→0 (sharp corner)
            // needs the most samples, so floor the divisor at 1 instead of
            // bailing to the coarse default.
            let span = max(cornerSpan, 1)
            let needed = Int(trailLength / span) * 8
            return max(120, min(needed, 1200))
        }()
        let capacity = steps + 1

        let startNS = strokeIndex == 0 ? bs.stroke1ColorStart.nsColor : bs.stroke2ColorStart.nsColor
        let endNS = strokeIndex == 0 ? bs.stroke1ColorEnd.nsColor : bs.stroke2ColorEnd.nsColor
        let colorStartV = SIMD4<Float>(Float(startNS.redComponent), Float(startNS.greenComponent),
                                       Float(startNS.blueComponent), 1.0)
        let colorEndV = SIMD4<Float>(Float(endNS.redComponent), Float(endNS.greenComponent),
                                     Float(endNS.blueComponent), 1.0)

        var ctx = TrailContext()
        ctx.centerPoints.reserveCapacity(capacity)
        ctx.widths.reserveCapacity(capacity)
        ctx.stripWidths.reserveCapacity(capacity)
        ctx.colors.reserveCapacity(capacity)
        ctx.alphas.reserveCapacity(capacity)
        ctx.tangents.reserveCapacity(capacity)

        let heightF = sceneSize.height
        let isMainTrail = (alpha == nil)
        let flashIntensity: Float = {
            guard isMainTrail, strokeIndex < strokeFlashIntensity.count else { return 0 }
            return strokeFlashIntensity[strokeIndex]
        }()
        let pulseFlashPeak = Float(borderSettings.pulseFlash)
        let flashWhiteMix = flashIntensity * pulseFlashPeak
        let flashAlphaBoost = CGFloat(flashIntensity * pulseFlashPeak * (0.5 / 0.7))
        let whiteV = SIMD4<Float>(1, 1, 1, 1)

        for stepIndex in 0...steps {
            let stepT = CGFloat(stepIndex) / CGFloat(steps)
            let stepTF = Float(stepT)
            let distAlong = stepT * effectiveTailLength * perimeterLength
            let rawDist = CGFloat(progress) * perimeterLength + (bs.clockwise ? distAlong : -distAlong)
            let wrapped = ((rawDist.truncatingRemainder(dividingBy: perimeterLength)) + perimeterLength)
                .truncatingRemainder(dividingBy: perimeterLength)

            let (segIdx, localDist) = segmentAt(distance: wrapped, segments: segments)
            let seg = segments[segIdx]
            let localT = seg.length > 0 ? min(localDist / seg.length, 1.0) : 0
            let (point, tangent) = seg.sample(at: localT)

            let baseW = (CGFloat(bs.baseWidth) + CGFloat(amplitude) * 3.0) * stepT
            ctx.centerPoints.append(CGPoint(x: point.x, y: heightF - point.y))
            ctx.widths.append(baseW * stripScale)
            ctx.stripWidths.append(baseW * 3.0 * stripScale)
            let baseColor = colorEndV + (colorStartV - colorEndV) * stepTF
            ctx.colors.append(baseColor + (whiteV - baseColor) * flashWhiteMix)
            let baseAlpha = isMainTrail ? stepT * CGFloat(opacity) : CGFloat(alpha ?? 0)
            ctx.alphas.append(min(1.0, baseAlpha + flashAlphaBoost))
            ctx.tangents.append(CGPoint(x: tangent.x, y: -tangent.y))
        }

        ctx.reverseAndFlipTangents()
        return ctx
    }

    func appendHeadFan(ctx: TrailContext, to vertices: inout [EffectVertex]) {
        let hCenter = ctx.centerPoints[0]
        let hDir = normalize(CGPoint(x: hCenter.x - ctx.centerPoints[1].x, y: hCenter.y - ctx.centerPoints[1].y))
        let hNormal = perp(hDir)
        let hRadius = ctx.widths[0] / 2
        let hColor = ctx.colors[0]
        let hAlpha = Float(ctx.alphas[0])
        let fanSteps = 16

        for fanIndex in 0...fanSteps {
            let angle = CGFloat(fanIndex) / CGFloat(fanSteps) * .pi
            let ox = hNormal.x * cos(angle) * hRadius + hDir.x * sin(angle) * hRadius
            let oy = hNormal.y * cos(angle) * hRadius + hDir.y * sin(angle) * hRadius
            vertices.append(EffectVertex(position: SIMD2<Float>(Float(hCenter.x), Float(hCenter.y)),
                                        color: hColor, alpha: hAlpha, edgeDist: 0.0))
            vertices.append(EffectVertex(position: SIMD2<Float>(Float(hCenter.x + ox), Float(hCenter.y + oy)),
                                        color: hColor, alpha: hAlpha, edgeDist: 1.0))
        }

        if let lastFan = vertices.last {
            let firstNormal = perp(normalize(CGPoint(x: ctx.centerPoints[1].x - hCenter.x,
                                                     y: ctx.centerPoints[1].y - hCenter.y)))
            let halfW = ctx.stripWidths[0] / 2
            // Match the body's clamped railA (+N) endpoint so a head sitting on a
            // corner doesn't reintroduce a fold at the fan→body seam.
            let (radius0, innerIsPlusN0) = localCurvature(ctx.centerPoints, at: 0)
            let off0 = clampedRailOffsets(halfW: halfW, radius: radius0, innerIsPlusN: innerIsPlusN0)
            vertices.append(lastFan)
            vertices.append(lastFan)
            vertices.append(EffectVertex(position: SIMD2<Float>(Float(hCenter.x + firstNormal.x * off0.hA),
                                                               Float(hCenter.y + firstNormal.y * off0.hA)),
                                        color: hColor, alpha: hAlpha, edgeDist: off0.edgeA))
        }
    }

    /// Local centerline radius magnitude + which rail side (+N) is concave,
    /// from three consecutive centerline points. Computed in render space
    /// (after the mirror + tangent-flip), so no sign bookkeeping is needed —
    /// the geometry already reflects every transform. Straight → .infinity.
    func localCurvature(_ points: [CGPoint], at i: Int) -> (radius: CGFloat, innerIsPlusN: Bool) {
        let n = points.count
        guard n >= 3 else { return (.infinity, true) }
        // Walk out to neighbours at least `minSpan` px away on each side. With
        // dense sampling (corner densification → up to 1200 samples) adjacent
        // points are sub-pixel apart; a circumradius from near-coincident points
        // is numerically garbage. A fixed-distance span keeps the triangle
        // well-conditioned at any sample density.
        let minSpan: CGFloat = 4
        func dist(_ p: CGPoint, _ q: CGPoint) -> CGFloat {
            let dx = p.x - q.x, dy = p.y - q.y
            return (dx * dx + dy * dy).squareRoot()
        }
        func walkOut(from start: Int, step: Int) -> Int {
            var j = start
            while j + step >= 0 && j + step <= n - 1 && dist(points[j + step], points[start]) < minSpan {
                j += step
            }
            let next = j + step
            return (next >= 0 && next <= n - 1) ? next : j
        }
        // Three well-spaced, distinct points bracketing i. At the head/tail
        // boundary (i==0 or n-1) the window can't straddle i, so shift it inward
        // (i, i+k, i+2k) — otherwise i=0 degenerates to radius=∞ and the
        // full-width head never clamps when it sits on a corner.
        let back = walkOut(from: i, step: -1)
        let fwd = walkOut(from: i, step: +1)
        let a: CGPoint, b: CGPoint, c: CGPoint
        if back == i {                       // near start: window forward of i
            let fwd2 = walkOut(from: fwd, step: +1)
            a = points[i]; b = points[fwd]; c = points[fwd2]
        } else if fwd == i {                 // near end: window behind i
            let back2 = walkOut(from: back, step: -1)
            a = points[back2]; b = points[back]; c = points[i]
        } else {
            a = points[back]; b = points[i]; c = points[fwd]
        }
        let abx = b.x - a.x, aby = b.y - a.y
        let acx = c.x - a.x, acy = c.y - a.y
        let cross = abx * acy - aby * acx          // signed 2×area; >0 = left turn
        let area2 = abs(cross)
        guard area2 > 1e-3 else { return (.infinity, cross > 0) }
        let bcx = c.x - b.x, bcy = c.y - b.y
        let ab = (abx * abx + aby * aby).squareRoot()
        let bc = (bcx * bcx + bcy * bcy).squareRoot()
        let ca = (acx * acx + acy * acy).squareRoot()
        let radius = (ab * bc * ca) / (2 * area2)  // circumradius = abc / (4·area)
        // Left turn → centre of curvature is left of travel = +N (perp) side,
        // so the +N rail is the concave/inner one that would fold.
        return (radius, cross > 0)
    }

    /// Clamp the inner (concave) rail's offset so it can't cross the centerline
    /// when halfW exceeds the local radius, and re-derive each rail's edgeDist
    /// from its true signed distance (normalised by the unclamped halfW). This
    /// keeps the edgeDist=0 bright core on the real centerline and leaves
    /// straight sections (radius .infinity ⇒ no clamp) byte-for-byte unchanged.
    func clampedRailOffsets(halfW: CGFloat, radius: CGFloat, innerIsPlusN: Bool) -> RailOffsets {
        guard halfW > 0 else { return RailOffsets(hA: 0, hB: 0, edgeA: -1, edgeB: 1) }
        let safe = min(halfW, 0.85 * radius)       // radius .infinity ⇒ halfW
        let hA = innerIsPlusN ? safe : halfW       // railA = +N side
        let hB = innerIsPlusN ? halfW : safe       // railB = −N side
        return RailOffsets(hA: hA, hB: hB, edgeA: Float(-hA / halfW), edgeB: Float(hB / halfW))
    }

    func appendBodyStrip(ctx: TrailContext, to vertices: inout [EffectVertex]) {
        let steps = ctx.centerPoints.count - 1
        for i in 0...steps {
            let point = ctx.centerPoints[i]
            let normal = perp(ctx.tangents[i])
            let halfW = ctx.stripWidths[i] / 2
            let (radius, innerIsPlusN) = localCurvature(ctx.centerPoints, at: i)
            let off = clampedRailOffsets(halfW: halfW, radius: radius, innerIsPlusN: innerIsPlusN)

            let color4 = ctx.colors[i]
            let alpha = Float(ctx.alphas[i])
            vertices.append(EffectVertex(position: SIMD2<Float>(Float(point.x + normal.x * off.hA),
                                                               Float(point.y + normal.y * off.hA)),
                                        color: color4, alpha: alpha, edgeDist: off.edgeA))
            vertices.append(EffectVertex(position: SIMD2<Float>(Float(point.x - normal.x * off.hB),
                                                               Float(point.y - normal.y * off.hB)),
                                        color: color4, alpha: alpha, edgeDist: off.edgeB))
        }
    }

    func buildTrailVertices(
        strokeIndex: Int,
        progress: Double,
        amplitude: Float,
        stripScale: CGFloat,
        alpha: Float?
    ) -> [EffectVertex] {
        let ctx = prepareEffectMesh(progress: progress, amplitude: amplitude, stripScale: stripScale,
                                   strokeIndex: strokeIndex, alpha: alpha)
        var vertices: [EffectVertex] = []
        vertices.reserveCapacity(ctx.centerPoints.count * 2 + 40)
        appendHeadFan(ctx: ctx, to: &vertices)
        appendBodyStrip(ctx: ctx, to: &vertices)
        return vertices
    }

    /// Audio amplitude driving a given stroke's width. Single stroke uses the
    /// combined L+R average; two strokes split L / R. Shared by the trail build
    /// and the debug overlay so both sample the identical geometry.
    func amplitude(forStroke strokeIndex: Int) -> Float {
        strokes.count == 1
            ? (smoothedLeft + smoothedRight) / 2
            : (strokeIndex == 0 ? smoothedLeft : smoothedRight)
    }

    func buildEffectMesh(strokeIndex: Int) -> EffectMesh {
        let amplitude = amplitude(forStroke: strokeIndex)
        let vertices = buildTrailVertices(
            strokeIndex: strokeIndex,
            progress: strokes[strokeIndex].progress,
            amplitude: amplitude,
            stripScale: 1.0,
            alpha: nil
        )
        return EffectMesh(vertices: vertices)
    }

    func buildScaledGhostMesh(
        strokeIndex: Int,
        amplitude: Float,
        widthScale: CGFloat,
        lengthScale: CGFloat,
        alpha: Float
    ) -> EffectMesh {
        let bs = borderSettings
        let bodyTailLength = Double(bs.tailLength)
        let ghostTailLength = bodyTailLength * Double(lengthScale)
        let progressDelta = bodyTailLength * (1.0 - Double(lengthScale)) * 0.5
        let bodyProgress = strokes[strokeIndex].progress
        let ghostProgress = bodyProgress + (bs.clockwise ? progressDelta : -progressDelta)

        var ctx = prepareEffectMesh(
            progress: ghostProgress,
            amplitude: amplitude,
            stripScale: widthScale,
            strokeIndex: strokeIndex,
            alpha: alpha,
            tailLengthOverride: ghostTailLength
        )
        guard ctx.centerPoints.count >= 2 else {
            return EffectMesh(vertices: [])
        }

        for i in 0..<ctx.stripWidths.count {
            ctx.stripWidths[i] = ctx.widths[i]
        }

        var vertices: [EffectVertex] = []
        vertices.reserveCapacity(ctx.centerPoints.count * 2 + 40)
        appendHeadFan(ctx: ctx, to: &vertices)
        appendBodyStrip(ctx: ctx, to: &vertices)

        for i in 0..<vertices.count {
            let v = vertices[i]
            vertices[i] = EffectVertex(
                position: v.position,
                color: v.color,
                alpha: v.alpha,
                edgeDist: 2.0
            )
        }
        return EffectMesh(vertices: vertices)
    }
}
