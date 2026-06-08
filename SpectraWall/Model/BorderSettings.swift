//
//  BorderSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import Foundation

struct BorderSettings: EffectSettings, Equatable {
    var strokeCount: Int
    var clockwise: Bool
    var speed: Double
    var tailLength: Double
    var baseWidth: Double
    var cornerRadius: Double
    var stroke1ColorStart: ColorData
    var stroke1ColorEnd: ColorData
    var stroke2ColorStart: ColorData
    var stroke2ColorEnd: ColorData
    var pulseAttack: Double
    var pulseRelease: Double
    var pulseThreshold: Double
    /// Flash brightness on the main trail at the moment a beat fires. 0 =
    /// no flash; 1 = lerp the trail colour all the way to white at peak.
    /// Alpha boost is derived from this so brightness/visibility move together.
    var pulseFlash: Double
    /// Whether a beat spawns a translucent ghost copy of the trail. Flash on
    /// the main trail still fires regardless.
    var ghostEnabled: Bool
    /// Ghost overall intensity (drives both width and length scale through
    /// fixed deltas; ratio stays constant). 0 = ghost = body; 1 = default;
    /// up to 2 = double the effect.
    var ghostSize: Double
    /// Ghost fill alpha at spawn (lifetime=0); fades to 0 over its lifetime.
    var ghostOpacity: Double
    /// Ghost decay speed. Lifetime ≈ 1 / ghostDecay seconds.
    var ghostDecay: Double

    static var defaults: BorderSettings {
        BorderSettings(
            strokeCount: 2,
            clockwise: true,
            speed: 0.05,
            tailLength: 0.15,
            baseWidth: 20.0,
            cornerRadius: 20.0,
            stroke1ColorStart: ColorData(red: 1.0, green: 0.8, blue: 0.1), // 尾：金黃
            stroke1ColorEnd: ColorData(red: 1.0, green: 1.0, blue: 0.4), // 頭：亮黃
            stroke2ColorStart: ColorData(red: 1.0, green: 0.1, blue: 0.4), // 尾：洋紅
            stroke2ColorEnd: ColorData(red: 1.0, green: 0.4, blue: 0.8), // 頭：粉紅
            pulseAttack: 0.85,
            pulseRelease: 0.1,
            pulseThreshold: 0.01,
            pulseFlash: 0.7,
            ghostEnabled: true,
            ghostSize: 0.9,
            ghostOpacity: 0.65,
            ghostDecay: 4.0
        )
    }

    mutating func resetToDefaults() {
        self = Self.defaults
    }
}

extension BorderSettings {
    /// Randomize numeric params within their spec ranges; each stroke gets a
    /// related head/tail colour pair. Topology (strokeCount, clockwise,
    /// ghostEnabled, pulseThreshold) stays put so the result is always usable.
    func randomized() -> BorderSettings {
        var s = self
        s.speed = BorderSpec.speed.random()
        s.tailLength = BorderSpec.tailLength.random()
        s.baseWidth = BorderSpec.baseWidth.random()
        s.cornerRadius = BorderSpec.cornerRadius.random()
        s.pulseAttack = BorderSpec.pulseAttack.random()
        s.pulseRelease = BorderSpec.pulseRelease.random()
        s.pulseFlash = BorderSpec.pulseFlash.random()
        s.ghostSize = BorderSpec.ghostSize.random()
        s.ghostOpacity = BorderSpec.ghostOpacity.random()
        s.ghostDecay = BorderSpec.ghostDecay.random()
        let s1 = RandomColor.relatedPair()
        s.stroke1ColorStart = s1.0
        s.stroke1ColorEnd = s1.1
        let s2 = RandomColor.relatedPair()
        s.stroke2ColorStart = s2.0
        s.stroke2ColorEnd = s2.1
        return s
    }
}

extension BorderSettings {
    // Custom init so v0.0.5 configs (which predate all the pulseFlash/ghost*
    // keys) still decode — those keys fall back to defaults. Encode is
    // auto-synthesised because CodingKeys map 1:1 to properties.
    enum CodingKeys: String, CodingKey {
        case strokeCount, clockwise, speed, tailLength, baseWidth, cornerRadius
        case stroke1ColorStart, stroke1ColorEnd, stroke2ColorStart, stroke2ColorEnd
        case pulseAttack, pulseRelease, pulseThreshold, pulseFlash
        case ghostEnabled, ghostSize, ghostOpacity, ghostDecay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            strokeCount: try c.decode(Int.self, forKey: .strokeCount),
            clockwise: try c.decode(Bool.self, forKey: .clockwise),
            speed: try c.decode(Double.self, forKey: .speed),
            tailLength: try c.decode(Double.self, forKey: .tailLength),
            baseWidth: try c.decode(Double.self, forKey: .baseWidth),
            cornerRadius: try c.decode(Double.self, forKey: .cornerRadius),
            stroke1ColorStart: try c.decode(ColorData.self, forKey: .stroke1ColorStart),
            stroke1ColorEnd: try c.decode(ColorData.self, forKey: .stroke1ColorEnd),
            stroke2ColorStart: try c.decode(ColorData.self, forKey: .stroke2ColorStart),
            stroke2ColorEnd: try c.decode(ColorData.self, forKey: .stroke2ColorEnd),
            pulseAttack: try c.decode(Double.self, forKey: .pulseAttack),
            pulseRelease: try c.decode(Double.self, forKey: .pulseRelease),
            pulseThreshold: try c.decode(Double.self, forKey: .pulseThreshold),
            pulseFlash: try c.decodeIfPresent(Double.self, forKey: .pulseFlash) ?? 0.7,
            ghostEnabled: try c.decodeIfPresent(Bool.self, forKey: .ghostEnabled) ?? true,
            ghostSize: try c.decodeIfPresent(Double.self, forKey: .ghostSize) ?? 0.9,
            ghostOpacity: try c.decodeIfPresent(Double.self, forKey: .ghostOpacity) ?? 0.65,
            ghostDecay: try c.decodeIfPresent(Double.self, forKey: .ghostDecay) ?? 4.0
        )
    }
}
