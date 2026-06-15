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
    /// Beat-spawned expanding rings (ghost-style: each beat spawns one, each
    /// fades out independently; several can be alive at once).
    var rippleEnabled: Bool
    /// Ring expansion rate in baseRadius units per second.
    var rippleSpeed: Double
    /// Ring alpha at spawn; fades to 0 over its lifetime.
    var rippleOpacity: Double
    /// Ring decay speed. Lifetime ≈ 1 / rippleDecay seconds.
    var rippleDecay: Double
    /// Minimum combined amplitude for the beat detector to spawn a ring —
    /// raise it so only hard beats ripple, quieter hits get filtered out.
    var rippleThreshold: Double
    /// Per-angle deformation of the inner disk driven by frequency bands
    /// (low bands push big lobes). 0 = perfect circle.
    var blobAmount: Double
    /// Continuous hue rotation applied after the low/high colour lerp, in
    /// cycles per second. 0 = off.
    var hueCycleSpeed: Double

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
            outerOpacity: 0.15,
            rippleEnabled: true,
            rippleSpeed: 1.5,
            rippleOpacity: 0.5,
            rippleDecay: 3.0,
            rippleThreshold: 0.01,
            blobAmount: 0.0,
            hueCycleSpeed: 0.0
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
        s.rippleSpeed = OrbSpec.rippleSpeed.random()
        s.rippleOpacity = OrbSpec.rippleOpacity.random()
        s.rippleDecay = OrbSpec.rippleDecay.random()
        s.blobAmount = OrbSpec.blobAmount.random()
        s.hueCycleSpeed = OrbSpec.hueCycleSpeed.random()
        let inner = RandomColor.relatedPair()
        s.innerColorLow = inner.0
        s.innerColorHigh = inner.1
        let outer = RandomColor.relatedPair()
        s.outerColorLow = outer.0
        s.outerColorHigh = outer.1
        return s
    }
}

extension OrbSettings {
    // Custom init so configs that predate the ripple keys still decode —
    // missing keys fall back to defaults. Encode is auto-synthesised because
    // CodingKeys map 1:1 to properties.
    enum CodingKeys: String, CodingKey {
        case boost, attack, release, baseRadius, outerRadiusMultiplier
        case innerColorLow, innerColorHigh, outerColorLow, outerColorHigh, outerOpacity
        case rippleEnabled, rippleSpeed, rippleOpacity, rippleDecay, rippleThreshold
        case blobAmount, hueCycleSpeed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            boost: try c.decode(Double.self, forKey: .boost),
            attack: try c.decode(Double.self, forKey: .attack),
            release: try c.decode(Double.self, forKey: .release),
            baseRadius: try c.decode(Double.self, forKey: .baseRadius),
            outerRadiusMultiplier: try c.decode(Double.self, forKey: .outerRadiusMultiplier),
            innerColorLow: try c.decode(ColorData.self, forKey: .innerColorLow),
            innerColorHigh: try c.decode(ColorData.self, forKey: .innerColorHigh),
            outerColorLow: try c.decode(ColorData.self, forKey: .outerColorLow),
            outerColorHigh: try c.decode(ColorData.self, forKey: .outerColorHigh),
            outerOpacity: try c.decode(Double.self, forKey: .outerOpacity),
            rippleEnabled: try c.decodeIfPresent(Bool.self, forKey: .rippleEnabled) ?? true,
            rippleSpeed: try c.decodeIfPresent(Double.self, forKey: .rippleSpeed) ?? 1.5,
            rippleOpacity: try c.decodeIfPresent(Double.self, forKey: .rippleOpacity) ?? 0.5,
            rippleDecay: try c.decodeIfPresent(Double.self, forKey: .rippleDecay) ?? 3.0,
            rippleThreshold: try c.decodeIfPresent(Double.self, forKey: .rippleThreshold) ?? 0.01,
            blobAmount: try c.decodeIfPresent(Double.self, forKey: .blobAmount) ?? 0.0,
            hueCycleSpeed: try c.decodeIfPresent(Double.self, forKey: .hueCycleSpeed) ?? 0.0
        )
    }
}
