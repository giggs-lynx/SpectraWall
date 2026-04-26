//
//  LayerSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI
import Combine

struct ColorData: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        red = c.redComponent
        green = c.greenComponent
        blue = c.blueComponent
        alpha = c.alphaComponent
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(nsColor)
    }
}

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

enum SpectrumColorMode: String, Codable, CaseIterable {
    case rainbow = "彩虹漸層"
    case solid = "單色"
}

class LayerSettings: ObservableObject, Codable, Identifiable {
    var id: UUID

    @Published var effectType: EffectType
    @Published var isVisible: Bool
    @Published var channelMode: ChannelMode
    @Published var name: String

    // MARK: - 共用位置
    @Published var positionX: Double
    @Published var positionY: Double
    @Published var opacity: Double

    // MARK: - Spectrum
    @Published var spectrumGain: Double
    @Published var spectrumPowerCurve: Double
    @Published var spectrumAttack: Double
    @Published var spectrumRelease: Double
    @Published var spectrumWidth: Double
    @Published var spectrumMaxHeight: Double
    @Published var spectrumColorMode: SpectrumColorMode
    @Published var spectrumSolidColor: ColorData

    // MARK: - Orb
    @Published var orbBoost: Double
    @Published var orbAttack: Double
    @Published var orbRelease: Double
    @Published var orbBaseRadius: Double
    @Published var orbOuterRadiusMultiplier: Double
    @Published var orbInnerColorLow: ColorData
    @Published var orbInnerColorHigh: ColorData
    @Published var orbOuterColorLow: ColorData
    @Published var orbOuterColorHigh: ColorData
    @Published var orbOuterOpacity: Double

    init(effectType: EffectType = .spectrum, name: String? = nil) {
        self.id = UUID()
        self.effectType = effectType
        self.isVisible = true
        self.channelMode = DefaultVal.channelMode
        self.name = if let name { name } else { effectType.rawValue }
        self.positionX = DefaultVal.positionX
        self.positionY = DefaultVal.positionY
        self.opacity = DefaultVal.opacity
        self.spectrumGain = DefaultVal.spectrumGain
        self.spectrumPowerCurve = DefaultVal.spectrumPowerCurve
        self.spectrumAttack = DefaultVal.spectrumAttack
        self.spectrumRelease = DefaultVal.spectrumRelease
        self.spectrumWidth = DefaultVal.spectrumWidth
        self.spectrumMaxHeight = DefaultVal.spectrumMaxHeight
        self.spectrumColorMode = DefaultVal.spectrumColorMode
        self.spectrumSolidColor = DefaultVal.spectrumSolidColor
        self.orbBoost = DefaultVal.orbBoost
        self.orbAttack = DefaultVal.orbAttack
        self.orbRelease = DefaultVal.orbRelease
        self.orbBaseRadius = DefaultVal.orbBaseRadius
        self.orbOuterRadiusMultiplier = DefaultVal.orbOuterRadiusMultiplier
        self.orbInnerColorLow = DefaultVal.orbInnerColorLow
        self.orbInnerColorHigh = DefaultVal.orbInnerColorHigh
        self.orbOuterColorLow = DefaultVal.orbOuterColorLow
        self.orbOuterColorHigh = DefaultVal.orbOuterColorHigh
        self.orbOuterOpacity = DefaultVal.orbOuterOpacity
    }
    
    convenience init(copying source: LayerSettings) {
        self.init(effectType: source.effectType, name: source.name + " 副本")
        self.isVisible = source.isVisible
        self.channelMode = source.channelMode
        self.positionX = source.positionX
        self.positionY = source.positionY
        self.opacity = source.opacity
        self.spectrumGain = source.spectrumGain
        self.spectrumPowerCurve = source.spectrumPowerCurve
        self.spectrumAttack = source.spectrumAttack
        self.spectrumRelease = source.spectrumRelease
        self.spectrumWidth = source.spectrumWidth
        self.spectrumMaxHeight = source.spectrumMaxHeight
        self.spectrumColorMode = source.spectrumColorMode
        self.spectrumSolidColor = source.spectrumSolidColor
        self.orbBoost = source.orbBoost
        self.orbAttack = source.orbAttack
        self.orbRelease = source.orbRelease
        self.orbBaseRadius = source.orbBaseRadius
        self.orbOuterRadiusMultiplier = source.orbOuterRadiusMultiplier
        self.orbInnerColorLow = source.orbInnerColorLow
        self.orbInnerColorHigh = source.orbInnerColorHigh
        self.orbOuterColorLow = source.orbOuterColorLow
        self.orbOuterColorHigh = source.orbOuterColorHigh
        self.orbOuterOpacity = source.orbOuterOpacity
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, effectType, isVisible, channelMode, name
        case positionX, positionY, opacity
        case spectrumGain, spectrumPowerCurve, spectrumAttack, spectrumRelease
        case spectrumWidth, spectrumMaxHeight, spectrumColorMode, spectrumSolidColor
        case orbBoost, orbAttack, orbRelease, orbBaseRadius, orbOuterRadiusMultiplier
        case orbInnerColorLow, orbInnerColorHigh
        case orbOuterColorLow, orbOuterColorHigh, orbOuterOpacity
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        effectType = try c.decode(EffectType.self, forKey: .effectType)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
        channelMode = try c.decode(ChannelMode.self, forKey: .channelMode)
        name = try c.decode(String.self, forKey: .name)
        positionX = try c.decode(Double.self, forKey: .positionX)
        positionY = try c.decode(Double.self, forKey: .positionY)
        opacity = try c.decode(Double.self, forKey: .opacity)
        spectrumGain = try c.decode(Double.self, forKey: .spectrumGain)
        spectrumPowerCurve = try c.decode(Double.self, forKey: .spectrumPowerCurve)
        spectrumAttack = try c.decode(Double.self, forKey: .spectrumAttack)
        spectrumRelease = try c.decode(Double.self, forKey: .spectrumRelease)
        spectrumWidth = try c.decode(Double.self, forKey: .spectrumWidth)
        spectrumMaxHeight = try c.decode(Double.self, forKey: .spectrumMaxHeight)
        spectrumColorMode = try c.decode(SpectrumColorMode.self, forKey: .spectrumColorMode)
        spectrumSolidColor = try c.decode(ColorData.self, forKey: .spectrumSolidColor)
        orbBoost = try c.decode(Double.self, forKey: .orbBoost)
        orbAttack = try c.decode(Double.self, forKey: .orbAttack)
        orbRelease = try c.decode(Double.self, forKey: .orbRelease)
        orbBaseRadius = try c.decode(Double.self, forKey: .orbBaseRadius)
        orbOuterRadiusMultiplier = try c.decodeIfPresent(Double.self, forKey: .orbOuterRadiusMultiplier) ?? DefaultVal.orbOuterRadiusMultiplier
        orbInnerColorLow = try c.decode(ColorData.self, forKey: .orbInnerColorLow)
        orbInnerColorHigh = try c.decode(ColorData.self, forKey: .orbInnerColorHigh)
        orbOuterColorLow = try c.decode(ColorData.self, forKey: .orbOuterColorLow)
        orbOuterColorHigh = try c.decode(ColorData.self, forKey: .orbOuterColorHigh)
        orbOuterOpacity = try c.decode(Double.self, forKey: .orbOuterOpacity)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(effectType, forKey: .effectType)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(channelMode, forKey: .channelMode)
        try c.encode(name, forKey: .name)

        try c.encode(positionX, forKey: .positionX)
        try c.encode(positionY, forKey: .positionY)
        try c.encode(opacity, forKey: .opacity)

        try c.encode(spectrumGain, forKey: .spectrumGain)
        try c.encode(spectrumPowerCurve, forKey: .spectrumPowerCurve)
        try c.encode(spectrumAttack, forKey: .spectrumAttack)
        try c.encode(spectrumRelease, forKey: .spectrumRelease)
        try c.encode(spectrumWidth, forKey: .spectrumWidth)
        try c.encode(spectrumMaxHeight, forKey: .spectrumMaxHeight)
        try c.encode(spectrumColorMode, forKey: .spectrumColorMode)
        try c.encode(spectrumSolidColor, forKey: .spectrumSolidColor)

        try c.encode(orbBoost, forKey: .orbBoost)
        try c.encode(orbAttack, forKey: .orbAttack)
        try c.encode(orbRelease, forKey: .orbRelease)
        try c.encode(orbBaseRadius, forKey: .orbBaseRadius)
        try c.encode(orbOuterRadiusMultiplier, forKey: .orbOuterRadiusMultiplier)
        try c.encode(orbInnerColorLow, forKey: .orbInnerColorLow)
        try c.encode(orbInnerColorHigh, forKey: .orbInnerColorHigh)
        try c.encode(orbOuterColorLow, forKey: .orbOuterColorLow)
        try c.encode(orbOuterColorHigh, forKey: .orbOuterColorHigh)
        try c.encode(orbOuterOpacity, forKey: .orbOuterOpacity)
    }

    func resetToDefaults() {
        isVisible = true
        channelMode = DefaultVal.channelMode
        positionX = DefaultVal.positionX
        positionY = DefaultVal.positionY
        opacity = DefaultVal.opacity

        switch effectType {
        case .spectrum:
            spectrumGain = DefaultVal.spectrumGain
            spectrumPowerCurve = DefaultVal.spectrumPowerCurve
            spectrumAttack = DefaultVal.spectrumAttack
            spectrumRelease = DefaultVal.spectrumRelease
            spectrumWidth = DefaultVal.spectrumWidth
            spectrumMaxHeight = DefaultVal.spectrumMaxHeight
            spectrumColorMode = DefaultVal.spectrumColorMode
            spectrumSolidColor = DefaultVal.spectrumSolidColor
        case .orb:
            orbBoost = DefaultVal.orbBoost
            orbAttack = DefaultVal.orbAttack
            orbRelease = DefaultVal.orbRelease
            orbBaseRadius = DefaultVal.orbBaseRadius
            orbOuterRadiusMultiplier = DefaultVal.orbOuterRadiusMultiplier
            orbInnerColorLow = DefaultVal.orbInnerColorLow
            orbInnerColorHigh = DefaultVal.orbInnerColorHigh
            orbOuterColorLow = DefaultVal.orbOuterColorLow
            orbOuterColorHigh = DefaultVal.orbOuterColorHigh
            orbOuterOpacity = DefaultVal.orbOuterOpacity
        }
    }
}

extension LayerSettings {
    struct DefaultVal {
        private init() {}

        static let positionX: Double = 0.5
        static let positionY: Double = 0.0
        static let opacity: Double = 1.0
        static let channelMode: ChannelMode = .stereo

        static let spectrumGain: Double = 1.8
        static let spectrumPowerCurve: Double = 1.5
        static let spectrumAttack: Double = 0.95
        static let spectrumRelease: Double = 0.2
        static let spectrumWidth: Double = 1.0
        static let spectrumMaxHeight: Double = 0.75
        static let spectrumColorMode: SpectrumColorMode = .rainbow
        static let spectrumSolidColor = ColorData(red: 1.0, green: 1.0, blue: 1.0)

        static let orbBoost: Double = 3.0
        static let orbAttack: Double = 0.6
        static let orbRelease: Double = 0.25
        static let orbBaseRadius: Double = 120
        static let orbOuterRadiusMultiplier: Double = 1.4
        static let orbInnerColorLow = ColorData(red: 0.2, green: 0.4, blue: 1.0)
        static let orbInnerColorHigh = ColorData(red: 0.8, green: 0.2, blue: 1.0)
        static let orbOuterColorLow = ColorData(red: 0.2, green: 0.4, blue: 1.0)
        static let orbOuterColorHigh = ColorData(red: 0.8, green: 0.2, blue: 1.0)
        static let orbOuterOpacity: Double = 0.15
    }
}
