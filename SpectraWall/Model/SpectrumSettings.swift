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

// MARK: - Spectrum Settings Structure

struct SpectrumSettings: EffectSettings, Equatable {
    var gain: Double
    var powerCurve: Double
    var attack: Double
    var release: Double
    
    var width: Double
    var maxHeight: Double
    var anchor: SpectrumAnchor
    
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
            anchor: .bottom,
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
    /// single). Topology/enums (anchor, colorSync) stay put so the result is
    /// always usable.
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
