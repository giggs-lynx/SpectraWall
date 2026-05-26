//
//  EffectType.swift
//  SpectraWall
//
//  Identifier for a kind of visual effect. RawRepresentable<String> instead of
//  enum so EffectRegistry can host new kinds at runtime — adding a fourth
//  effect type only requires a new `static let` and an EffectDescriptor
//  registration, no changes to call-site switches beyond their default arm.
//
//  rawValue strings are the on-disk Codable form. Keep them stable; existing
//  scene-<uuid>.json files store these strings literally.
//

import Foundation

struct EffectType: Hashable, Codable, RawRepresentable {
    let rawValue: String

    static let spectrum = EffectType(rawValue: "Spectrum")
    static let orb      = EffectType(rawValue: "Orb")
    static let border   = EffectType(rawValue: "Border")
}

extension EffectType {
    /// Localised label for UI. Falls back to the raw type string so new
    /// effects can plug in without touching a centralised lookup.
    var localized: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: rawValue)
    }
}
