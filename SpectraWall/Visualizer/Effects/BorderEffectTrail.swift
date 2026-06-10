//
//  BorderEffectTrail.swift
//  SpectraWall
//

import CoreGraphics
import AppKit
import simd

// MARK: - Trail Vertex Building

extension BorderEffect {

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

    /// Emit one quad per centerline segment, each carrying its endpoints + the
    /// capsule radius so `border_fragment` can shade by true distance to the
    /// segment. Replaces the old offset-rail strip whose inner rail folded at
    /// tight corners (the spike). Round head/tail caps fall out of the capsule
    /// SDF for free — no separate head fan. Output is a plain triangle list.
    func appendCapsuleStrip(ctx: TrailContext, to vertices: inout [EffectVertex]) {
        let n = ctx.centerPoints.count
        guard n >= 2 else { return }
        for i in 0..<(n - 1) {
            let a = ctx.centerPoints[i]
            let b = ctx.centerPoints[i + 1]
            // One radius per segment, taking the wider of the two endpoints so a
            // tapering trail never gaps between capsules; the max blend resolves
            // the resulting overlap into one continuous glow.
            let halfW = max(ctx.stripWidths[i], ctx.stripWidths[i + 1]) / 2
            guard halfW > 0 else { continue }
            let segA = SIMD2<Float>(Float(a.x), Float(a.y))
            let segB = SIMD2<Float>(Float(b.x), Float(b.y))
            let radius = Float(halfW)
            let color = ctx.colors[i]
            let alpha = Float(ctx.alphas[i])

            // Quad = the capsule's oriented bounding box, padded 1.15× to keep
            // the exp() glow tail that extends just past the nominal radius.
            let pad = halfW * 1.15
            let dx = b.x - a.x, dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            let axis = len > 1e-6 ? CGPoint(x: dx / len, y: dy / len) : CGPoint(x: 1, y: 0)
            let nrm = perp(axis)
            let ax = CGPoint(x: axis.x * pad, y: axis.y * pad)
            let nx = CGPoint(x: nrm.x * pad, y: nrm.y * pad)

            func vert(_ p: CGPoint) -> EffectVertex {
                EffectVertex(position: SIMD2<Float>(Float(p.x), Float(p.y)),
                             color: color, alpha: alpha, edgeDist: 0,
                             segA: segA, segB: segB, radius: radius)
            }
            let c0 = CGPoint(x: a.x - ax.x + nx.x, y: a.y - ax.y + nx.y)
            let c1 = CGPoint(x: a.x - ax.x - nx.x, y: a.y - ax.y - nx.y)
            let c2 = CGPoint(x: b.x + ax.x + nx.x, y: b.y + ax.y + nx.y)
            let c3 = CGPoint(x: b.x + ax.x - nx.x, y: b.y + ax.y - nx.y)
            // Two triangles; winding is irrelevant (no back-face culling).
            vertices.append(vert(c0)); vertices.append(vert(c1)); vertices.append(vert(c2))
            vertices.append(vert(c2)); vertices.append(vert(c1)); vertices.append(vert(c3))
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
        vertices.reserveCapacity(ctx.centerPoints.count * 6)
        appendCapsuleStrip(ctx: ctx, to: &vertices)
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
        return EffectMesh(vertices: vertices, primitiveType: .triangle)
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
        vertices.reserveCapacity(ctx.centerPoints.count * 6)
        appendCapsuleStrip(ctx: ctx, to: &vertices)

        // Flag every vertex as uniform-fill (solid silhouette, no glow falloff).
        // Mutate in place so the capsule's segA/segB/radius survive.
        for i in 0..<vertices.count {
            vertices[i].edgeDist = 2.0
        }
        return EffectMesh(vertices: vertices, primitiveType: .triangle)
    }
}
