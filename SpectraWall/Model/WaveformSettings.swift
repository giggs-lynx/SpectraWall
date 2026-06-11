//
//  WaveformSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/6/11.
//

import Foundation

struct WaveformSettings: EffectSettings, Equatable {
    /// Visible history, in seconds. The wave scrolls left; new data enters
    /// on the right.
    var windowSeconds: Double
    var gain: Double
    /// Band amplitude as a fraction of screen height (per side of the
    /// centerline).
    var maxHeight: Double
    var colorSettings: ChannelColorSettings

    static var defaults: WaveformSettings {
        WaveformSettings(
            windowSeconds: 3.0,
            gain: 2.0,
            maxHeight: 0.2,
            colorSettings: .init()
        )
    }

    mutating func resetToDefaults() {
        self = Self.defaults
    }
}

extension WaveformSettings {
    /// Randomize numeric params within their spec ranges; colours follow the
    /// existing colorMode.
    func randomized() -> WaveformSettings {
        var s = self
        s.windowSeconds = WaveformSpec.windowSeconds.random()
        s.gain = WaveformSpec.gain.random()
        s.maxHeight = WaveformSpec.maxHeight.random()
        switch s.colorSettings.colorMode {
        case .rainbow:
            break
        case .gradient:
            let pair = RandomColor.relatedPair()
            s.colorSettings.gradientColorLow = pair.0
            s.colorSettings.gradientColorHigh = pair.1
        case .solid:
            s.colorSettings.solidColor = RandomColor.pleasant()
        }
        return s
    }
}
