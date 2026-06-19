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

    /// LED-matrix texture: darkened grid lines overlaid inside the fill.
    var pixelGridEnabled: Bool
    /// Grid cell size in points (screen-fixed).
    var pixelGridSpacing: Double
    /// How dark the grid lines are (0 = invisible, 1 = black).
    var pixelGridOpacity: Double
    /// Draw a constant-width white line tracing the top peak envelope.
    var peakOutlineEnabled: Bool
    var peakOutlineWidth: Double

    var colorSettings: ChannelColorSettings

    static var defaults: WaveformSettings {
        WaveformSettings(
            windowSeconds: 3.0,
            gain: 2.0,
            maxHeight: 0.2,
            pixelGridEnabled: false,
            pixelGridSpacing: 12,
            pixelGridOpacity: 0.3,
            peakOutlineEnabled: false,
            peakOutlineWidth: 1.5,
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

extension WaveformSettings {
    // Custom init so presets that predate the grid/outline fields still decode —
    // missing keys fall back to their defaults. Encode is auto-synthesised.
    enum CodingKeys: String, CodingKey {
        case windowSeconds, gain, maxHeight
        case pixelGridEnabled, pixelGridSpacing, pixelGridOpacity, peakOutlineEnabled, peakOutlineWidth
        case colorSettings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            windowSeconds: try c.decode(Double.self, forKey: .windowSeconds),
            gain: try c.decode(Double.self, forKey: .gain),
            maxHeight: try c.decode(Double.self, forKey: .maxHeight),
            pixelGridEnabled: try c.decodeIfPresent(Bool.self, forKey: .pixelGridEnabled) ?? false,
            pixelGridSpacing: try c.decodeIfPresent(Double.self, forKey: .pixelGridSpacing) ?? 12,
            pixelGridOpacity: try c.decodeIfPresent(Double.self, forKey: .pixelGridOpacity) ?? 0.3,
            peakOutlineEnabled: try c.decodeIfPresent(Bool.self, forKey: .peakOutlineEnabled) ?? false,
            peakOutlineWidth: try c.decodeIfPresent(Double.self, forKey: .peakOutlineWidth) ?? 1.5,
            colorSettings: try c.decode(ChannelColorSettings.self, forKey: .colorSettings)
        )
    }
}
