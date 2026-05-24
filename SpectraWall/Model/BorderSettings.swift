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
    /// Beat-spawned ghost intensity. 0 = no visible pulse (ghost = body),
    /// 1 = default look, up to 2 = double effect. Drives both width and
    /// length scale through fixed deltas; ratio between them stays constant.
    var pulseSize: Double
    /// Ghost fill alpha at spawn (lifetime=0). Fades to 0 over the ghost's
    /// lifetime; this is the starting visibility.
    var pulseOpacity: Double
    /// How fast the ghost decays. Higher = faster fadeout / shorter lifetime.
    /// Lifetime ≈ 1 / pulseDecay seconds.
    var pulseDecay: Double

    static var defaults: BorderSettings {
        BorderSettings(
            strokeCount: 2,
            clockwise: true,
            speed: 0.05,
            tailLength: 0.15,
            baseWidth: 20.0,
            cornerRadius: 20.0,
            stroke1ColorStart: ColorData(red: 1.0, green: 0.8, blue: 0.1),  // 尾：金黃
            stroke1ColorEnd:   ColorData(red: 1.0, green: 1.0, blue: 0.4),  // 頭：亮黃
            stroke2ColorStart: ColorData(red: 1.0, green: 0.1, blue: 0.4),  // 尾：洋紅
            stroke2ColorEnd:   ColorData(red: 1.0, green: 0.4, blue: 0.8),  // 頭：粉紅
            pulseAttack: 0.85,
            pulseRelease: 0.1,
            pulseThreshold: 0.01,
            pulseSize: 0.9,
            pulseOpacity: 0.65,
            pulseDecay: 4.0
        )
    }

    mutating func resetToDefaults() {
        self = Self.defaults
    }
}

extension BorderSettings {
    // Custom Codable so older on-disk configs without `pulseSize` still
    // decode — they fall back to 1.0 (the default look).
    enum CodingKeys: String, CodingKey {
        case strokeCount, clockwise, speed, tailLength, baseWidth, cornerRadius
        case stroke1ColorStart, stroke1ColorEnd, stroke2ColorStart, stroke2ColorEnd
        case pulseAttack, pulseRelease, pulseThreshold
        case pulseSize, pulseOpacity, pulseDecay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            strokeCount:       try c.decode(Int.self,       forKey: .strokeCount),
            clockwise:         try c.decode(Bool.self,      forKey: .clockwise),
            speed:             try c.decode(Double.self,    forKey: .speed),
            tailLength:        try c.decode(Double.self,    forKey: .tailLength),
            baseWidth:         try c.decode(Double.self,    forKey: .baseWidth),
            cornerRadius:      try c.decode(Double.self,    forKey: .cornerRadius),
            stroke1ColorStart: try c.decode(ColorData.self, forKey: .stroke1ColorStart),
            stroke1ColorEnd:   try c.decode(ColorData.self, forKey: .stroke1ColorEnd),
            stroke2ColorStart: try c.decode(ColorData.self, forKey: .stroke2ColorStart),
            stroke2ColorEnd:   try c.decode(ColorData.self, forKey: .stroke2ColorEnd),
            pulseAttack:       try c.decode(Double.self,    forKey: .pulseAttack),
            pulseRelease:      try c.decode(Double.self,    forKey: .pulseRelease),
            pulseThreshold:    try c.decode(Double.self,    forKey: .pulseThreshold),
            pulseSize:         try c.decodeIfPresent(Double.self, forKey: .pulseSize)    ?? 0.9,
            pulseOpacity:      try c.decodeIfPresent(Double.self, forKey: .pulseOpacity) ?? 0.65,
            pulseDecay:        try c.decodeIfPresent(Double.self, forKey: .pulseDecay)   ?? 4.0
        )
    }
}
