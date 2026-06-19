//
//  SpectrumSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import Foundation

// MARK: - Spectrum Anchor Type

enum SpectrumAnchor: String, Codable, CaseIterable {
    case bottom
    case top
    case left
    case right

    var localized: LocalizedStringResource {
        switch self {
        case .bottom: return "Bottom"
        case .top:    return "Top"
        case .left:   return "Left"
        case .right:  return "Right"
        }
    }
}

// MARK: - Spectrum Style

enum SpectrumStyle: String, Codable, CaseIterable {
    case bars
    case curve
    case line

    var localized: LocalizedStringResource {
        switch self {
        case .bars:  return "Bars"
        case .curve: return "Curve"
        case .line:  return "Line"
        }
    }
}

// MARK: - Spectrum Settings Structure

struct SpectrumSettings: EffectSettings, Equatable {
    var gain: Double
    var powerCurve: Double
    var attack: Double
    var release: Double
    
    var width: Double
    var maxHeight: Double
    /// Displayed bar count (24 / 48 / 96). The analyzer always produces 96
    /// semitone bins; fewer bars are adjacent-bin averages — never more than
    /// the source resolution.
    var barCount: Int
    var anchor: SpectrumAnchor
    /// Bars grow symmetrically to both sides of the base line (each side up
    /// to maxHeight, so total span is 2× the single-sided extent).
    var mirror: Bool
    /// How the spectrum is drawn: discrete bars, a smooth filled silhouette,
    /// or the same smooth curve stroked as a constant-width line.
    var style: SpectrumStyle
    /// Classic EQ peak caps: a brightened marker holds each bar's recent peak
    /// briefly, then falls. Bars style only.
    var capsEnabled: Bool
    /// Round the tip of each bar (both ends when mirrored). Bars style only.
    var roundedTips: Bool

    /// LED-matrix texture: darkened grid lines overlaid inside the fill.
    var pixelGridEnabled: Bool
    /// Grid cell size in points (screen-fixed).
    var pixelGridSpacing: Double
    /// How dark the grid lines are (0 = invisible, 1 = black).
    var pixelGridOpacity: Double
    /// Draw a constant-width white line tracing the bar tips / curve.
    var peakOutlineEnabled: Bool
    var peakOutlineWidth: Double

    var colorSync: Bool
    var colorSettings: ChannelColorSettings
    var leftColorSettings: ChannelColorSettings
    var rightColorSettings: ChannelColorSettings

    static var defaults: SpectrumSettings {
        SpectrumSettings(
            gain: 2.6,
            powerCurve: 2.0,
            attack: 0.95,
            release: 0.2,
            width: 1.0,
            maxHeight: 0.35,
            barCount: 96,
            anchor: .bottom,
            mirror: false,
            style: .bars,
            capsEnabled: false,
            roundedTips: false,
            pixelGridEnabled: false,
            pixelGridSpacing: 12,
            pixelGridOpacity: 0.3,
            peakOutlineEnabled: false,
            peakOutlineWidth: 1.5,
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

extension SpectrumSettings {
    /// Randomize numeric params within their spec ranges. Colours follow each
    /// channel's existing colorMode (rainbow → none, gradient → pair, solid →
    /// single). Topology/enums (anchor, mirror, style, colorSync) stay put so
    /// the result is always usable.
    func randomized() -> SpectrumSettings {
        var s = self
        s.gain = SpectrumSpec.gain.random()
        s.powerCurve = SpectrumSpec.powerCurve.random()
        s.attack = SpectrumSpec.attack.random()
        s.release = SpectrumSpec.release.random()
        s.width = SpectrumSpec.width.random()
        s.maxHeight = SpectrumSpec.maxHeight.random()
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

extension SpectrumSettings {
    // Custom init so configs/presets that predate `mirror` still decode —
    // the missing key falls back to its default. Encode is auto-synthesised
    // because CodingKeys map 1:1 to properties.
    enum CodingKeys: String, CodingKey {
        case gain, powerCurve, attack, release
        case width, maxHeight, barCount, anchor, mirror, style, capsEnabled, roundedTips
        case pixelGridEnabled, pixelGridSpacing, pixelGridOpacity, peakOutlineEnabled, peakOutlineWidth
        case colorSync, colorSettings, leftColorSettings, rightColorSettings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Hand-edited configs can hold arbitrary ints; clamp to the supported
        // set so the effect never allocates off-spec bin arrays.
        let rawBars = try c.decodeIfPresent(Int.self, forKey: .barCount) ?? 96
        self.init(
            gain: try c.decode(Double.self, forKey: .gain),
            powerCurve: try c.decode(Double.self, forKey: .powerCurve),
            attack: try c.decode(Double.self, forKey: .attack),
            release: try c.decode(Double.self, forKey: .release),
            width: try c.decode(Double.self, forKey: .width),
            maxHeight: try c.decode(Double.self, forKey: .maxHeight),
            barCount: [24, 48, 96].contains(rawBars) ? rawBars : 96,
            anchor: try c.decode(SpectrumAnchor.self, forKey: .anchor),
            mirror: try c.decodeIfPresent(Bool.self, forKey: .mirror) ?? false,
            style: try c.decodeIfPresent(SpectrumStyle.self, forKey: .style) ?? .bars,
            capsEnabled: try c.decodeIfPresent(Bool.self, forKey: .capsEnabled) ?? false,
            roundedTips: try c.decodeIfPresent(Bool.self, forKey: .roundedTips) ?? false,
            pixelGridEnabled: try c.decodeIfPresent(Bool.self, forKey: .pixelGridEnabled) ?? false,
            pixelGridSpacing: try c.decodeIfPresent(Double.self, forKey: .pixelGridSpacing) ?? 12,
            pixelGridOpacity: try c.decodeIfPresent(Double.self, forKey: .pixelGridOpacity) ?? 0.3,
            peakOutlineEnabled: try c.decodeIfPresent(Bool.self, forKey: .peakOutlineEnabled) ?? false,
            peakOutlineWidth: try c.decodeIfPresent(Double.self, forKey: .peakOutlineWidth) ?? 1.5,
            colorSync: try c.decode(Bool.self, forKey: .colorSync),
            colorSettings: try c.decode(ChannelColorSettings.self, forKey: .colorSettings),
            leftColorSettings: try c.decode(ChannelColorSettings.self, forKey: .leftColorSettings),
            rightColorSettings: try c.decode(ChannelColorSettings.self, forKey: .rightColorSettings)
        )
    }
}
