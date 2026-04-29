//
//  EffectSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import Foundation

protocol EffectSettings: Codable {
    static var defaults: Self { get }
    mutating func resetToDefaults()
}
