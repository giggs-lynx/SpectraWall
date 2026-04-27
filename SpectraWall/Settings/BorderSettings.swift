//
//  BorderSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import Foundation

struct BorderSettings: EffectSettings {
    var strokeCount: Int
    var clockwise: Bool
    var speed: Double
    var stroke1ColorStart: ColorData
    var stroke1ColorEnd: ColorData
    var stroke2ColorStart: ColorData
    var stroke2ColorEnd: ColorData
    var tailLength: Double
    var baseWidth: Double
    var cornerRadius: Double
    var pulseAttack: Double
    var pulseRelease: Double

    static var defaults: BorderSettings {
        BorderSettings(
            strokeCount: 1,
            clockwise: true,
            speed: 0.15,
            stroke1ColorStart: ColorData(red: 0.0, green: 0.8, blue: 1.0),
            stroke1ColorEnd: ColorData(red: 0.6, green: 0.0, blue: 1.0),
            stroke2ColorStart: ColorData(red: 1.0, green: 0.3, blue: 0.0),
            stroke2ColorEnd: ColorData(red: 1.0, green: 0.8, blue: 0.0),
            tailLength: 0.3,
            baseWidth: 10.0,
            cornerRadius: 20.0,
            pulseAttack: 0.9,
            pulseRelease: 0.15
        )
    }

    mutating func resetToDefaults() {
        self = Self.defaults
    }
}
