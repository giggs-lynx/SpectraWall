//
//  RadialSpectrumEffectDebug.swift
//  SpectraWall
//
//  Debug overlay for the radial spectrum: hub circle, max-extent circle(s),
//  and one radial centerline per bar at its current length — all from the
//  same radialGeometry()/barAngle()/barRadialSpan() math as the mesh so the
//  wireframe cannot drift from the real bars.
//

import CoreGraphics
import Foundation
import simd

extension RadialSpectrumEffect {

    private enum DebugColor {
        static let hub     = SIMD4<Float>(0, 1, 1, 1)   // cyan    hub circle
        static let ceiling = SIMD4<Float>(1, 0, 1, 1)   // magenta max extent
        static let bar     = SIMD4<Float>(0, 1, 0, 1)   // green   bar centerlines
    }

    func buildRadialDebug(into canvas: inout DebugCanvas) {
        let geo = radialGeometry()
        let center = CGPoint(x: CGFloat(geo.center.x), y: CGFloat(geo.center.y))

        canvas.point(center, color: DebugColor.ceiling)
        drawCircle(center: center, radius: CGFloat(geo.hubRadius),
                   color: DebugColor.hub, into: &canvas)
        drawCircle(center: center, radius: CGFloat(geo.hubRadius + geo.maxExtent),
                   color: DebugColor.ceiling, into: &canvas)
        if geo.mirror {
            drawCircle(center: center, radius: CGFloat(max(geo.hubRadius * 0.2, geo.hubRadius - geo.maxExtent)),
                       color: DebugColor.ceiling, into: &canvas)
        }

        for i in 0..<binCount {
            let angle = CGFloat(barAngle(i))
            let (rIn, rOut) = barRadialSpan(i, geo: geo)
            let a = CGPoint(x: center.x + cos(angle) * CGFloat(rIn),
                            y: center.y + sin(angle) * CGFloat(rIn))
            let b = CGPoint(x: center.x + cos(angle) * CGFloat(rOut),
                            y: center.y + sin(angle) * CGFloat(rOut))
            canvas.segment(a, b, color: DebugColor.bar, width: 1.5)
        }
    }

    private func drawCircle(center: CGPoint, radius: CGFloat,
                            color: SIMD4<Float>, into canvas: inout DebugCanvas) {
        guard radius > 0 else { return }
        var pts: [CGPoint] = []
        pts.reserveCapacity(49)
        for k in 0...48 {
            let t = CGFloat(k) / 48 * 2 * .pi
            pts.append(CGPoint(x: center.x + cos(t) * radius, y: center.y + sin(t) * radius))
        }
        canvas.polyline(pts, color: color, width: 1.5)
    }
}
