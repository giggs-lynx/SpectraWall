//
//  LayerSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI
import Combine
import Foundation

enum EffectType: String, Codable, CaseIterable {
    case spectrum = "Spectrum"
    case orb = "Orb"
    case border = "Border"
    
    var localized: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: rawValue)
    }
}

enum ChannelMode: String, Codable, CaseIterable {
    case stereo = "stereo"
    case left = "left"
    case right = "right"
    case mono = "mono"
    
    var localized: LocalizedStringResource {
        switch self {
        case .stereo: return "Stereo"
        case .left:   return "Left Channel"
        case .right:  return "Right Channel"
        case .mono:   return "Mono"
        }
    }
}

class LayerSettings: ObservableObject, Identifiable {
    var id: UUID
    @Published var name: String
    @Published var isVisible: Bool
    @Published var channelMode: ChannelMode
    @Published var positionX: Double
    @Published var positionY: Double
    @Published var opacity: Double
    @Published var effectType: EffectType
    @Published var effectSettings: any EffectSettings

    init(effectType: EffectType = .spectrum, name: String? = nil) {
        self.id = UUID()
        self.effectType = effectType
        self.name = name ?? effectType.rawValue
        self.isVisible = true
        self.channelMode = .stereo
        self.positionX = 0.5
        self.positionY = 0.0
        self.opacity = 1.0
        self.effectSettings = Self.defaultSettings(for: effectType)
    }

    convenience init(copying source: LayerSettings) {
        self.init(effectType: source.effectType, name: source.name + " Copy")
        self.isVisible = source.isVisible
        self.channelMode = source.channelMode
        self.positionX = source.positionX
        self.positionY = source.positionY
        self.opacity = source.opacity
        self.effectSettings = source.effectSettings
    }
    
    required convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let effectType = try c.decode(EffectType.self, forKey: .effectType)
        self.init(effectType: effectType)

        id = try c.decode(UUID.self, forKey: .id) // id is let, need to handle here
        name = try c.decode(String.self, forKey: .name)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
        channelMode = try c.decode(ChannelMode.self, forKey: .channelMode)
        positionX = try c.decode(Double.self, forKey: .positionX)
        positionY = try c.decode(Double.self, forKey: .positionY)
        opacity = try c.decode(Double.self, forKey: .opacity)

        switch effectType {
        case .spectrum:
            effectSettings = try c.decode(SpectrumSettings.self, forKey: .effectSettings)
        case .orb:
            effectSettings = try c.decode(OrbSettings.self, forKey: .effectSettings)
        case .border:
            effectSettings = try c.decode(BorderSettings.self, forKey: .effectSettings)
        }
    }

    static func defaultSettings(for effectType: EffectType) -> any EffectSettings {
        switch effectType {
        case .spectrum: return SpectrumSettings.defaults
        case .orb:      return OrbSettings.defaults
        case .border:   return BorderSettings.defaults
        }
    }

    func resetToDefaults() {
        isVisible = true
        channelMode = .stereo
        positionX = 0.5
        positionY = 0.0
        opacity = 1.0
        effectSettings.resetToDefaults()
    }
}

// MARK: - Codable

extension LayerSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, isVisible, channelMode
        case positionX, positionY, opacity
        case effectType, effectSettings
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(channelMode, forKey: .channelMode)
        try c.encode(positionX, forKey: .positionX)
        try c.encode(positionY, forKey: .positionY)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(effectType, forKey: .effectType)

        switch effectSettings {
        case let s as SpectrumSettings:
            try c.encode(s, forKey: .effectSettings)
        case let s as OrbSettings:
            try c.encode(s, forKey: .effectSettings)
        case let s as BorderSettings:
            try c.encode(s, forKey: .effectSettings)
        default:
            break
        }
    }
}
