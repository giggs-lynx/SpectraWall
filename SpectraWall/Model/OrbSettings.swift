//
//  OrbSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import Foundation

struct OrbSettings: EffectSettings, Equatable {
    var boost: Double
    var attack: Double
    var release: Double
    var baseRadius: Double
    var outerRadiusMultiplier: Double
    var innerColorLow: ColorData
    var innerColorHigh: ColorData
    var outerColorLow: ColorData
    var outerColorHigh: ColorData
    var outerOpacity: Double

    static var defaults: OrbSettings {
        OrbSettings(
            boost: 3.0,
            attack: 0.95,
            release: 0.4,
            baseRadius: 80,
            outerRadiusMultiplier: 1.4,
            innerColorLow: ColorData(red: 0.2, green: 0.4, blue: 1.0),
            innerColorHigh: ColorData(red: 0.8, green: 0.2, blue: 1.0),
            outerColorLow: ColorData(red: 0.2, green: 0.4, blue: 1.0),
            outerColorHigh: ColorData(red: 0.8, green: 0.2, blue: 1.0),
            outerOpacity: 0.15
        )
    }

    mutating func resetToDefaults() {
        self = Self.defaults
    }
}

extension OrbSettings {
    /// Randomize numeric params within their spec ranges; inner/outer colours
    /// each get a related low/high pair.
    func randomized() -> OrbSettings {
        var s = self
        s.boost = OrbSpec.boost.random()
        s.attack = OrbSpec.attack.random()
        s.release = OrbSpec.release.random()
        s.baseRadius = OrbSpec.baseRadius.random()
        s.outerRadiusMultiplier = OrbSpec.outerRadiusMultiplier.random()
        s.outerOpacity = OrbSpec.outerOpacity.random()
        let inner = RandomColor.relatedPair()
        s.innerColorLow = inner.0
        s.innerColorHigh = inner.1
        let outer = RandomColor.relatedPair()
        s.outerColorLow = outer.0
        s.outerColorHigh = outer.1
        return s
    }
}
