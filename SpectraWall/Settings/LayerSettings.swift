//
//  LayerSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI
import Combine

enum EffectType: String, Codable, CaseIterable {
    case spectrum = "Spectrum"
    case orb = "Orb"
}

enum ChannelMode: String, Codable, CaseIterable {
    case stereo = "立體聲"
    case left = "左聲道"
    case right = "右聲道"
    case mono = "單聲道（混音）"
}

class LayerSettings: ObservableObject, Codable, Identifiable {
    let id: UUID

    @Published var effectType: EffectType
    @Published var channelMode: ChannelMode = .stereo
    @Published var isVisible: Bool

    // Spectrum
    @Published var spectrumGain: Double
    @Published var spectrumPowerCurve: Double
    @Published var spectrumAttack: Double
    @Published var spectrumRelease: Double

    // Orb
    @Published var orbBoost: Double
    @Published var orbAttack: Double
    @Published var orbRelease: Double

    init(effectType: EffectType = .spectrum) {
        self.id = UUID()
        self.effectType = effectType
        self.isVisible = true

        self.spectrumGain = 1.8
        self.spectrumPowerCurve = 1.5
        self.spectrumAttack = 0.95
        self.spectrumRelease = 0.2

        self.orbBoost = 3.0
        self.orbAttack = 0.6
        self.orbRelease = 0.25
    }

    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, effectType, isVisible
        case spectrumGain, spectrumPowerCurve, spectrumAttack, spectrumRelease
        case orbBoost, orbAttack, orbRelease
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        effectType = try c.decode(EffectType.self, forKey: .effectType)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
        spectrumGain = try c.decode(Double.self, forKey: .spectrumGain)
        spectrumPowerCurve = try c.decode(Double.self, forKey: .spectrumPowerCurve)
        spectrumAttack = try c.decode(Double.self, forKey: .spectrumAttack)
        spectrumRelease = try c.decode(Double.self, forKey: .spectrumRelease)
        orbBoost = try c.decode(Double.self, forKey: .orbBoost)
        orbAttack = try c.decode(Double.self, forKey: .orbAttack)
        orbRelease = try c.decode(Double.self, forKey: .orbRelease)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(effectType, forKey: .effectType)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(spectrumGain, forKey: .spectrumGain)
        try c.encode(spectrumPowerCurve, forKey: .spectrumPowerCurve)
        try c.encode(spectrumAttack, forKey: .spectrumAttack)
        try c.encode(spectrumRelease, forKey: .spectrumRelease)
        try c.encode(orbBoost, forKey: .orbBoost)
        try c.encode(orbAttack, forKey: .orbAttack)
        try c.encode(orbRelease, forKey: .orbRelease)
    }

    func resetToDefaults() {
        switch effectType {
        case .spectrum:
            spectrumGain = 1.8
            spectrumPowerCurve = 1.5
            spectrumAttack = 0.95
            spectrumRelease = 0.2
        case .orb:
            orbBoost = 3.0
            orbAttack = 0.6
            orbRelease = 0.25
        }
    }
}
