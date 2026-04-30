//
//  ChannelColorSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI
import AppKit

// MARK: - Color Data Container

struct ColorData: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: NSColor) {
        // 使用更具語意化的變數名 'convertedColor' 取代 'c'
        let convertedColor = color.usingColorSpace(.deviceRGB) ?? color
        red = Double(convertedColor.redComponent)
        green = Double(convertedColor.greenComponent)
        blue = Double(convertedColor.blueComponent)
        alpha = Double(convertedColor.alphaComponent)
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

// MARK: - Color Mode Type

enum ChannelColorMode: String, Codable, CaseIterable {
    case rainbow
    case gradient
    case solid

    var localized: LocalizedStringResource {
        switch self {
        case .rainbow:  return "Rainbow"
        case .gradient: return "Gradient"
        case .solid:    return "Solid"
        }
    }
}

// MARK: - Channel Color Settings

struct ChannelColorSettings: Codable, Equatable {
    var colorMode: ChannelColorMode = .rainbow
    var gradientColorLow: ColorData = ColorData(red: 0.0, green: 0.4, blue: 1.0)
    var gradientColorHigh: ColorData = ColorData(red: 1.0, green: 0.2, blue: 0.8)
    var solidColor: ColorData = ColorData(red: 1.0, green: 1.0, blue: 1.0)
}
