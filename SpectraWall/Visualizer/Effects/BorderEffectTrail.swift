//
//  BorderEffectTrail.swift
//  SpectraWall
//

import CoreGraphics
import AppKit
import simd

// MARK: - Trail Vertex Building

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
            guard cornerSpan > 0 else { return 120 }
            let needed = Int(trailLength / cornerSpan) * 8
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
            vertices.append(lastFan)
            vertices.append(lastFan)
            vertices.append(EffectVertex(position: SIMD2<Float>(Float(hCenter.x + firstNormal.x * halfW),
                                                               Float(hCenter.y + firstNormal.y * halfW)),
                                        color: hColor, alpha: hAlpha, edgeDist: -1.0))
        }
    }

    func appendBodyStrip(ctx: TrailContext, to vertices: inout [EffectVertex]) {
        let steps = ctx.centerPoints.count - 1
        for i in 0...steps {
            let point = ctx.centerPoints[i]
            let normal = perp(ctx.tangents[i])
            let halfW = ctx.stripWidths[i] / 2

            let color4 = ctx.colors[i]
            let alpha = Float(ctx.alphas[i])
            vertices.append(EffectVertex(position: SIMD2<Float>(Float(point.x + normal.x * halfW),
                                                               Float(point.y + normal.y * halfW)),
                                        color: color4, alpha: alpha, edgeDist: -1.0))
            vertices.append(EffectVertex(position: SIMD2<Float>(Float(point.x - normal.x * halfW),
                                                               Float(point.y - normal.y * halfW)),
                                        color: color4, alpha: alpha, edgeDist: 1.0))
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
