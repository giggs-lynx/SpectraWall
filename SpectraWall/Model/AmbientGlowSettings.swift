//
//  AmbientGlowSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/6/11.
//

import Foundation

// MARK: - Glow Placement

enum GlowPlacement: String, Codable, CaseIterable {
    case edges
    case bottom
    case top

    var localized: LocalizedStringResource {
        switch self {
        case .edges:  return "Edges"
        case .bottom: return "Bottom"
        case .top:    return "Top"
        }
    }
}

// MARK: - Ambient Glow Settings

struct AmbientGlowSettings: EffectSettings, Equatable {
    var placement: GlowPlacement
    /// Glow depth as a fraction of the screen's shorter side.
    var size: Double
    /// Peak alpha at full amplitude.
    var intensity: Double
    var attack: Double
    var release: Double
    /// Colour slides low → high with the smoothed amplitude, like Orb.
    var colorLow: ColorData
    var colorHigh: ColorData

    static var defaults: AmbientGlowSettings {
        AmbientGlowSettings(
            placement: .edges,
            size: 0.15,
            intensity: 0.5,
            attack: 0.95,
            release: 0.4,
            colorLow: ColorData(red: 0.1, green: 0.2, blue: 0.6),
            colorHigh: ColorData(red: 0.7, green: 0.3, blue: 0.9)
        )
    }

    mutating func resetToDefaults() {
        self = Self.defaults
    }
}

extension AmbientGlowSettings {
    /// Randomize numeric params within their spec ranges; colours get a
    /// related pair. Topology (placement) stays put.
    func randomized() -> AmbientGlowSettings {
        var s = self
        s.size = AmbientGlowSpec.size.random()
        s.intensity = AmbientGlowSpec.intensity.random()
        s.attack = AmbientGlowSpec.attack.random()
        s.release = AmbientGlowSpec.release.random()
        let pair = RandomColor.relatedPair()
        s.colorLow = pair.0
        s.colorHigh = pair.1
        return s
    }
}
