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
    
    static var defaults: BorderSettings {
        BorderSettings(
            strokeCount: 2,
            clockwise: true,
            speed: 0.15,
            tailLength: 0.3,
            baseWidth: 10.0,
            cornerRadius: 20.0,
            stroke1ColorStart: ColorData(red: 0.8, green: 0.1, blue: 1.0), // 尾：深紫
            stroke1ColorEnd: ColorData(red: 1.0, green: 0.4, blue: 1.0),   // 頭：亮粉紫
            stroke2ColorStart: ColorData(red: 0.1, green: 0.4, blue: 1.0), // 尾：深藍
            stroke2ColorEnd: ColorData(red: 0.4, green: 0.8, blue: 1.0),   // 頭：亮藍
            pulseAttack: 0.9,
            pulseRelease: 0.15,
            pulseThreshold: 0.01
        )
    }
    
    mutating func resetToDefaults() {
        self = Self.defaults
    }
}
