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
    struct BorderSegment {
        var length: CGFloat
        var isArc: Bool
        var startPoint: CGPoint = .zero
        var endPoint: CGPoint = .zero
        var center: CGPoint = .zero
        var radius: CGFloat = 0
        var startAngle: CGFloat = 0
        var endAngle: CGFloat = 0
        
        func point(at localT: CGFloat) -> CGPoint {
            if isArc {
                let angle = startAngle + (endAngle - startAngle) * localT
                return CGPoint(x: center.x + radius * cos(angle),
                               y: center.y + radius * sin(angle))
            } else {
                return CGPoint(
                    x: startPoint.x + (endPoint.x - startPoint.x) * localT,
                    y: startPoint.y + (endPoint.y - startPoint.y) * localT
                )
            }
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
        
        let width = max(0, sceneSize.width - inset * 2)
        let height = max(0, sceneSize.height - inset * 2)
        let radius = max(CGFloat(bs.cornerRadius) - inset, 0)
        let pi = CGFloat.pi
        
        let segs: [BorderSegment] = [
            BorderSegment(
                length: max(0, width - 2 * radius), isArc: false,
                startPoint: CGPoint(x: inset + radius, y: inset),
                endPoint: CGPoint(x: inset + width - radius, y: inset)),
            BorderSegment(
                length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + width - radius, y: inset + radius),
                radius: radius, startAngle: -pi / 2, endAngle: 0),
            BorderSegment(
                length: max(0, height - 2 * radius), isArc: false,
                startPoint: CGPoint(x: inset + width, y: inset + radius),
                endPoint: CGPoint(x: inset + width, y: inset + height - radius)),
            BorderSegment(
                length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + width - radius, y: inset + height - radius),
                radius: radius, startAngle: 0, endAngle: pi / 2),
            BorderSegment(
                length: max(0, width - 2 * radius), isArc: false,
                startPoint: CGPoint(x: inset + width - radius, y: inset + height),
                endPoint: CGPoint(x: inset + radius, y: inset + height)),
            BorderSegment(
                length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + radius, y: inset + height - radius),
                radius: radius, startAngle: pi / 2, endAngle: pi),
            BorderSegment(
                length: max(0, height - 2 * radius), isArc: false,
                startPoint: CGPoint(x: inset, y: inset + height - radius),
                endPoint: CGPoint(x: inset, y: inset + radius)),
            BorderSegment(
                length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + radius, y: inset + radius),
                radius: radius, startAngle: pi, endAngle: 3 * pi / 2)
        ]
        
        segmentCache = segs
        cachedSceneSize = sceneSize
        cachedCornerRadius = bs.cornerRadius
        return segs
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
            let point = seg.point(at: localT)
            
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
            points.append(seg.point(at: localT))
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
    
    private struct ArcInfo {
        var center: CGPoint
        var radius: CGFloat
    }

    private struct TrailContext {
        var centerPoints: [CGPoint] = []
        var widths: [CGFloat] = []
        var stripWidths: [CGFloat] = []
        var colors: [SIMD4<Float>] = []  // pre-converted; avoids per-step NSColor alloc
        var alphas: [CGFloat] = []
        var arcInfos: [ArcInfo?] = []    // nil on straight segments; arc center is y-flipped
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
        let arcLength = CGFloat.pi / 2 * max(CGFloat(bs.cornerRadius) - inset, 0)
        let trailLength = CGFloat(bs.tailLength) * perimeterLength
        let steps: Int = {
            guard arcLength > 0 else { return 120 }
            let needed = Int(trailLength / arcLength) * 8
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
        ctx.arcInfos.reserveCapacity(capacity)

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
            let point = seg.point(at: localT)

            let baseW = (CGFloat(bs.baseWidth) + CGFloat(amplitude) * 3.0) * stepT
            // Fold y-flip into the append to avoid a separate map pass after the loop.
            ctx.centerPoints.append(CGPoint(x: point.x, y: heightF - point.y))
            ctx.widths.append(baseW)
            ctx.stripWidths.append(baseW * 3.0 * stripScale)
            // SIMD lerp: register-only ops, zero heap allocation per step.
            ctx.colors.append(colorEndV + (colorStartV - colorEndV) * stepTF)
            ctx.alphas.append(alpha != nil ? CGFloat(alpha ?? 0) : stepT)
            if seg.isArc {
                // y-flip the arc center to match centerPoints coordinate space.
                ctx.arcInfos.append(ArcInfo(center: CGPoint(x: seg.center.x, y: heightF - seg.center.y),
                                            radius: seg.radius))
            } else {
                ctx.arcInfos.append(nil)
            }
        }

        ctx.centerPoints.reverse()
        ctx.widths.reverse()
        ctx.stripWidths.reverse()
        ctx.colors.reverse()
        ctx.alphas.reverse()
        ctx.arcInfos.reverse()
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

            // For arc sections use the analytic outward normal (point → away from arc center).
            // This is exact regardless of sampling density, and unambiguously points outward.
            // For straight sections fall back to the central-difference tangent normal.
            let normal: CGPoint
            let innerHalfW: CGFloat
            let halfW = ctx.stripWidths[i] / 2

            if let arc = ctx.arcInfos[i] {
                let dx = point.x - arc.center.x
                let dy = point.y - arc.center.y
                let d  = sqrt(dx * dx + dy * dy)
                normal = d > 0 ? CGPoint(x: dx / d, y: dy / d)
                               : perp(normalize(CGPoint(x: ctx.centerPoints[min(i+1,steps)].x - point.x,
                                                        y: ctx.centerPoints[min(i+1,steps)].y - point.y)))
                // Keep a positive inner arc radius so inner vertices don't all collapse to
                // arc.center. Collapsing causes 30+ overlapping triangles at each corner with
                // additive blending → bright dot artifact. The 15% floor keeps inner vertices
                // spread along a small inner arc while staying close to center.
                let minInnerRadius: CGFloat = max(1.0, arc.radius * 0.15)
                innerHalfW = min(halfW, max(0, arc.radius - minInnerRadius))
            } else {
                if i == 0 {
                    normal = perp(normalize(CGPoint(x: ctx.centerPoints[1].x - point.x,
                                                    y: ctx.centerPoints[1].y - point.y)))
                } else if i == steps {
                    normal = perp(normalize(CGPoint(x: point.x - ctx.centerPoints[i - 1].x,
                                                    y: point.y - ctx.centerPoints[i - 1].y)))
                } else {
                    normal = perp(normalize(CGPoint(x: ctx.centerPoints[i + 1].x - ctx.centerPoints[i - 1].x,
                                                    y: ctx.centerPoints[i + 1].y - ctx.centerPoints[i - 1].y)))
                }
                innerHalfW = halfW
            }

            let color4 = ctx.colors[i]
            let alpha  = Float(ctx.alphas[i])
            // normal points outward (away from arc center / away from screen interior).
            // outer vertex: +normal side;  inner vertex: -normal side, clamped at arc sections.
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
