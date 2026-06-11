//
//  RadialSpectrumSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/6/11.
//

import Foundation

struct RadialSpectrumSettings: EffectSettings, Equatable {
    var gain: Double
    var powerCurve: Double
    var attack: Double
    var release: Double

    /// Radius of the empty hub the bars sit on, in points.
    var innerRadius: Double
    /// Longest bar length, in points.
    var maxExtent: Double
    /// Bars grow both inward and outward from the hub circle instead of
    /// outward only (same vocabulary as Spectrum's mirror).
    var mirror: Bool

    var colorSync: Bool
    var colorSettings: ChannelColorSettings
    var leftColorSettings: ChannelColorSettings
    var rightColorSettings: ChannelColorSettings

    static var defaults: RadialSpectrumSettings {
        RadialSpectrumSettings(
            gain: 2.6,
            powerCurve: 2.0,
            attack: 0.95,
            release: 0.2,
            innerRadius: 120,
            maxExtent: 80,
            mirror: false,
            colorSync: true,
            colorSettings: .init(),
            leftColorSettings: .init(),
            rightColorSettings: .init()
        )
    }

    mutating func resetToDefaults() {
        self = Self.defaults
    }
}

extension RadialSpectrumSettings {
    /// Randomize numeric params within their spec ranges; colours follow each
    /// channel's existing colorMode. Topology (mirror, colorSync) stays put.
    func randomized() -> RadialSpectrumSettings {
        var s = self
        s.gain = RadialSpectrumSpec.gain.random()
        s.powerCurve = RadialSpectrumSpec.powerCurve.random()
        s.attack = RadialSpectrumSpec.attack.random()
        s.release = RadialSpectrumSpec.release.random()
        s.innerRadius = RadialSpectrumSpec.innerRadius.random()
        s.maxExtent = RadialSpectrumSpec.maxExtent.random()
        s.colorSettings = Self.randomizedColors(s.colorSettings)
        s.leftColorSettings = Self.randomizedColors(s.leftColorSettings)
        s.rightColorSettings = Self.randomizedColors(s.rightColorSettings)
        return s
    }

    private static func randomizedColors(_ c: ChannelColorSettings) -> ChannelColorSettings {
        var out = c
        switch c.colorMode {
        case .rainbow:
            break
        case .gradient:
            let pair = RandomColor.relatedPair()
            out.gradientColorLow = pair.0
            out.gradientColorHigh = pair.1
        case .solid:
            out.solidColor = RandomColor.pleasant()
        }
        return out
    }
}
