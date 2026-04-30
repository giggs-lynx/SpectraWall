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
