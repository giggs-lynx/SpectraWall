//
//  BorderEffectDebug.swift
//  SpectraWall
//
//  Debug overlay for the border trail. Draws the capsule skeleton that the SDF
//  fragment (border_fragment) shades from: the centerline polyline plus radius
//  rings sampled along it, so the glow envelope is visible as a wireframe and
//  the head/tail round caps are explicit.
//

import CoreGraphics
import Foundation
import simd

extension BorderEffect {

    private enum DebugColor {
        static let centerline = SIMD4<Float>(0, 1, 0, 1)   // green  centerline
        static let ring       = SIMD4<Float>(0, 1, 1, 1)   // cyan   capsule radius
        static let cap        = SIMD4<Float>(1, 0, 1, 1)   // magenta head / tail cap
    }

    /// Centerline samples between drawn radius rings, and ring tessellation.
    private static let ringStride = 12
    private static let ringSegments = 20

    func buildBorderDebug(into canvas: inout DebugCanvas) {
        for strokeIndex in 0..<strokes.count {
            // Same args as buildEffectMesh → the skeleton matches the rendered mesh.
            let ctx = prepareEffectMesh(
                progress: strokes[strokeIndex].progress,
                amplitude: amplitude(forStroke: strokeIndex),
                stripScale: 1.0,
                strokeIndex: strokeIndex,
                alpha: nil
            )
            let n = ctx.centerPoints.count
            guard n >= 2 else { continue }

            canvas.polyline(ctx.centerPoints, color: DebugColor.centerline, width: 1.5)

            // Radius rings trace the capsule envelope (the glow's nominal edge).
            for i in stride(from: 0, to: n, by: Self.ringStride) {
                drawRing(center: ctx.centerPoints[i], radius: ctx.stripWidths[i] / 2,
                         color: i == 0 ? DebugColor.cap : DebugColor.ring, into: &canvas)
            }
            // Always mark the tail cap (the strided loop may skip the last sample).
            drawRing(center: ctx.centerPoints[n - 1], radius: ctx.stripWidths[n - 1] / 2,
                     color: DebugColor.cap, into: &canvas)
        }
    }

    /// Draw a closed polygon approximating the capsule's radius circle.
    private func drawRing(center: CGPoint, radius: CGFloat,
                          color: SIMD4<Float>, into canvas: inout DebugCanvas) {
        guard radius > 0 else { return }
        var pts: [CGPoint] = []
        pts.reserveCapacity(Self.ringSegments + 1)
        for k in 0...Self.ringSegments {
            let t = CGFloat(k) / CGFloat(Self.ringSegments) * 2 * .pi
            pts.append(CGPoint(x: center.x + cos(t) * radius, y: center.y + sin(t) * radius))
        }
        canvas.polyline(pts, color: color, width: 1.5)
    }
}
