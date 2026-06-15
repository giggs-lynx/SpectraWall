//
//  OrbEffectDebug.swift
//  SpectraWall
//
//  Debug overlay for the orb. Draws the centre marker plus the inner-disk,
//  outer-glow and baseRadius rings. Rings reuse the fan tessellation
//  (fanSegments) so the wireframe shows the actual rendered polygon, and the
//  radii come from the same orbGeometry() the mesh is built from.
//

import CoreGraphics
import Foundation
import simd

extension OrbEffect {

    private enum DebugColor {
        static let center = SIMD4<Float>(1, 0, 1, 1)   // magenta centre marker
        static let inner  = SIMD4<Float>(0, 1, 0, 1)   // green   inner disk edge
        static let outer  = SIMD4<Float>(0, 1, 1, 1)   // cyan    outer glow edge
        static let base   = SIMD4<Float>(1, 1, 1, 1)   // white   baseRadius (scale = 1)
    }

    func buildOrbDebug(into canvas: inout DebugCanvas) {
        let geo = orbGeometry()
        let center = CGPoint(x: CGFloat(geo.center.x), y: CGFloat(geo.center.y))

        canvas.point(center, color: DebugColor.center)
        canvas.circle(center: center, radius: CGFloat(geo.outerRadius),
                      color: DebugColor.outer, width: 1.5)
        canvas.circle(center: center, radius: CGFloat(geo.baseRadius),
                      color: DebugColor.base, width: 1.5)
        let blob = debugBlobAmount
        if blob > 0 {
            // Deformed rim can't use canvas.circle; tessellate by the same policy
            // keyed on innerRadius so it matches the mesh fan.
            let segs = circleSegments(forRadius: geo.innerRadius)
            var pts: [CGPoint] = []
            pts.reserveCapacity(segs + 1)
            for k in 0...segs {
                let t = CGFloat(k) / CGFloat(segs) * 2 * .pi
                let r = CGFloat(geo.innerRadius * (1 + blob * blobValue(at: Float(t))))
                pts.append(CGPoint(x: center.x + cos(t) * r, y: center.y + sin(t) * r))
            }
            canvas.polyline(pts, color: DebugColor.inner, width: 1.5)
        } else {
            canvas.circle(center: center, radius: CGFloat(geo.innerRadius),
                          color: DebugColor.inner, width: 1.5)
        }
        for radius in currentRippleRadii() {
            canvas.circle(center: center, radius: CGFloat(radius),
                          color: DebugColor.outer, width: 1.5)
        }
    }
}
