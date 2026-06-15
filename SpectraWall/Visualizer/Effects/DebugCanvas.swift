//
//  DebugCanvas.swift
//  SpectraWall
//
//  Tiny immediate-mode helper for the debug overlay subsystem. Effects build a
//  geometry skeleton (lines, points) into a DebugCanvas in their `drawDebug`
//  hook; the result is one flat-colour `.triangle` mesh submitted to the
//  renderer's debug channel. Lines are emitted as quads (2 triangles) so width
//  is controllable and no degenerate-strip bookkeeping is needed.
//
//  Coordinates are render space — the same space effects submit their main mesh
//  in (the debug vertex shader normalises by screenSize).
//

import CoreGraphics
import Metal
import simd

/// Segment count for a circle of the given radius, scaled so facets stay below
/// ~0.4pt of sag (imperceptible) on big circles while small ones stay cheap.
/// Shared by the Orb mesh and every debug ring so a wireframe tessellates
/// identically to the geometry it traces. Sag s ≈ r·(π/N)²/2 → N = π·√(r/2s).
func circleSegments(forRadius radius: Float) -> Int {
    let sag: Float = 0.4
    let ideal = Float.pi * (max(0, radius) / (2 * sag)).squareRoot()
    return min(128, max(24, Int(ideal.rounded(.up))))
}

struct DebugCanvas {
    private var vertices: [EffectVertex] = []

    /// True when nothing was drawn — lets callers skip submitting (and avoid
    /// registering an empty debug entry, which would otherwise hide the host
    /// effect's normal mesh while drawing nothing).
    var isEmpty: Bool { vertices.count < 3 }

    /// One straight segment as a width-`width` quad.
    mutating func segment(_ a: CGPoint, _ b: CGPoint,
                          color: SIMD4<Float>, width: CGFloat = 2) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return }
        let nx = -dy / len * (width / 2)
        let ny = dx / len * (width / 2)
        let a0 = SIMD2<Float>(Float(a.x + nx), Float(a.y + ny))
        let a1 = SIMD2<Float>(Float(a.x - nx), Float(a.y - ny))
        let b0 = SIMD2<Float>(Float(b.x + nx), Float(b.y + ny))
        let b1 = SIMD2<Float>(Float(b.x - nx), Float(b.y - ny))
        appendTriangle(a0, a1, b0, color: color)
        appendTriangle(a1, b1, b0, color: color)
    }

    /// Connected polyline. Each adjacent pair becomes a `segment`.
    mutating func polyline(_ points: [CGPoint],
                           color: SIMD4<Float>, width: CGFloat = 2) {
        guard points.count >= 2 else { return }
        for i in 0..<(points.count - 1) {
            segment(points[i], points[i + 1], color: color, width: width)
        }
    }

    /// Closed circle outline, auto-tessellated by radius (see circleSegments).
    mutating func circle(center: CGPoint, radius: CGFloat,
                         color: SIMD4<Float>, width: CGFloat = 2) {
        guard radius > 0 else { return }
        let segs = circleSegments(forRadius: Float(radius))
        var pts: [CGPoint] = []
        pts.reserveCapacity(segs + 1)
        for k in 0...segs {
            let t = CGFloat(k) / CGFloat(segs) * 2 * .pi
            pts.append(CGPoint(x: center.x + cos(t) * radius, y: center.y + sin(t) * radius))
        }
        polyline(pts, color: color, width: width)
    }

    /// Small axis-aligned square marker centred on `p`.
    mutating func point(_ p: CGPoint, color: SIMD4<Float>, size: CGFloat = 6) {
        let h = size / 2
        let v0 = SIMD2<Float>(Float(p.x - h), Float(p.y - h))
        let v1 = SIMD2<Float>(Float(p.x + h), Float(p.y - h))
        let v2 = SIMD2<Float>(Float(p.x + h), Float(p.y + h))
        let v3 = SIMD2<Float>(Float(p.x - h), Float(p.y + h))
        appendTriangle(v0, v1, v2, color: color)
        appendTriangle(v0, v2, v3, color: color)
    }

    func makeMesh() -> EffectMesh {
        EffectMesh(vertices: vertices, primitiveType: .triangle)
    }

    private mutating func appendTriangle(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>,
                                         _ p2: SIMD2<Float>, color: SIMD4<Float>) {
        vertices.append(EffectVertex(position: p0, color: color, alpha: 1, edgeDist: 0))
        vertices.append(EffectVertex(position: p1, color: color, alpha: 1, edgeDist: 0))
        vertices.append(EffectVertex(position: p2, color: color, alpha: 1, edgeDist: 0))
    }
}
