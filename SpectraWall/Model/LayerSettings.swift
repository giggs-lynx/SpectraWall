//
//  LayerSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI
import Combine
import Foundation

enum ChannelMode: String, Codable, CaseIterable {
    case stereo, left, right, mono
    
    var localized: LocalizedStringResource {
        switch self {
        case .stereo: return "Stereo"
        case .left:   return "Left Channel"
        case .right:  return "Right Channel"
        case .mono:   return "Mono"
        }
    }
}

// MARK: - Main Layer Settings

class LayerSettings: ObservableObject, Identifiable, Codable {
    /// Runtime-only identity for SwiftUI ForEach. Not persisted to JSON; each
    /// decode generates a fresh UUID. Layers have no cross-session reference
    /// (no equivalent of activeSceneIndex), so this is purely an in-memory tag.
    var id: UUID

    @Published var name: String
    @Published var isVisible: Bool
    @Published var channelMode: ChannelMode
    @Published var positionX: Double
    @Published var positionY: Double
    @Published var opacity: Double
    @Published var effectType: EffectType
    @Published var effectSettings: any EffectSettings

    // MARK: CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id, name, isVisible, channelMode
        case positionX, positionY, opacity
        case effectType, effectSettings
    }

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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let effectType = try container.decode(EffectType.self, forKey: .effectType)

        self.init(effectType: effectType)

        // id stays optional in decoder so post-migration JSON (no id field)
        // still decodes; falls back to the fresh UUID set in init().
        if let storedID = try? container.decodeIfPresent(UUID.self, forKey: .id) {
            self.id = storedID
        }
        self.name = try container.decode(String.self, forKey: .name)
        self.isVisible = try container.decode(Bool.self, forKey: .isVisible)
        self.channelMode = try container.decode(ChannelMode.self, forKey: .channelMode)
        self.positionX = try container.decode(Double.self, forKey: .positionX)
        self.positionY = try container.decode(Double.self, forKey: .positionY)
        self.opacity = try container.decode(Double.self, forKey: .opacity)

        if let descriptor = EffectRegistry.descriptor(for: effectType) {
            // Hand the codec the sub-decoder for `effectSettings`. Reading the
            // nested value via `superDecoder(forKey:)` is wire-compatible with
            // the prior `container.decode(SpectrumSettings.self, forKey:)`
            // approach — both pull the same JSON object out of the keyed
            // container and let the concrete settings type drive its own
            // Codable synthesis.
            let nested = try container.superDecoder(forKey: .effectSettings)
            self.effectSettings = try descriptor.settingsCodec.decode(nested)
        }
        // else: unknown effect type — leave the Spectrum default already
        // installed by self.init(effectType:). C8's UI dispatch keeps this
        // from surfacing in practice; we just don't crash.
    }

    /// Default settings struct for a kind of effect. Driven by the registry
    /// so adding a fourth effect requires no change here.
    static func defaultSettings(for effectType: EffectType) -> any EffectSettings {
        EffectRegistry.descriptor(for: effectType)?.makeDefaultSettings()
            ?? SpectrumSettings.defaults
    }

    func resetToDefaults() {
        isVisible = true
        channelMode = .stereo
        positionX = 0.5
        positionY = 0.0
        opacity = 1.0
        effectSettings.resetToDefaults()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // id is intentionally not encoded — see property doc.
        try container.encode(name, forKey: .name)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(channelMode, forKey: .channelMode)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(effectType, forKey: .effectType)

        if let descriptor = EffectRegistry.descriptor(for: effectType) {
            let nested = container.superEncoder(forKey: .effectSettings)
            try descriptor.settingsCodec.encode(effectSettings, nested)
        }
    }
}
