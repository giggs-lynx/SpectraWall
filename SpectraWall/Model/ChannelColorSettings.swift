//
//  ChannelColorSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI
import AppKit
import OSLog

// MARK: - Color Data Container

struct ColorData: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: NSColor) {
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

    // MARK: - Codable as ARGB hex string

    /// Serializes as `#AARRGGBB` (8 hex digits). Decodes either the hex form
    /// or the legacy `{ red, green, blue, alpha }` object form so migrations
    /// from the pre-XDG era still load.
    private enum LegacyCodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let hex = try? single.decode(String.self) {
            // A malformed hex is treated as a recoverable typo rather than a
            // fatal decode error — one bad colour shouldn't sink the entire
            // scene file. Fall back to default white and log so the user can
            // find it.
            if let parsed = try? ColorData.parseHex(hex) {
                self = parsed
            } else {
                AppLog.persist.error("""
                    Invalid colour hex \"\(hex, privacy: .public)\" — falling \
                    back to default white.
                    """)
                self = ColorData(red: 1, green: 1, blue: 1, alpha: 1)
            }
            return
        }
        let kv = try decoder.container(keyedBy: LegacyCodingKeys.self)
        red = try kv.decode(Double.self, forKey: .red)
        green = try kv.decode(Double.self, forKey: .green)
        blue = try kv.decode(Double.self, forKey: .blue)
        alpha = try kv.decode(Double.self, forKey: .alpha)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }

    var hexString: String {
        let a = UInt8(clamping: Int((alpha * 255).rounded()))
        let r = UInt8(clamping: Int((red * 255).rounded()))
        let g = UInt8(clamping: Int((green * 255).rounded()))
        let b = UInt8(clamping: Int((blue * 255).rounded()))
        return String(format: "#%02X%02X%02X%02X", a, r, g, b)
    }

    private enum HexError: Error { case invalid(String) }

    private static func parseHex(_ raw: String) throws -> ColorData {
        let trimmed = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard let value = UInt32(trimmed, radix: 16) else {
            throw HexError.invalid(raw)
        }
        let alpha, red, green, blue: Double
        switch trimmed.count {
        case 6: // RRGGBB → alpha = 1.0
            alpha = 1.0
            red   = Double((value >> 16) & 0xFF) / 255
            green = Double((value >>  8) & 0xFF) / 255
            blue  = Double( value        & 0xFF) / 255
        case 8: // AARRGGBB
            alpha = Double((value >> 24) & 0xFF) / 255
            red   = Double((value >> 16) & 0xFF) / 255
            green = Double((value >>  8) & 0xFF) / 255
            blue  = Double( value        & 0xFF) / 255
        default:
            throw HexError.invalid(raw)
        }
        return ColorData(red: red, green: green, blue: blue, alpha: alpha)
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
