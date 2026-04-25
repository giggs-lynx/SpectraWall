//
//  VisualizerSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI
import Combine

class VisualizerSettings: ObservableObject {
    static let shared = VisualizerSettings()

    // MARK: - 公用（Analyzer 層）
    @AppStorage("bassAttenuation") var bassAttenuation: Double = 30.0

    // MARK: - Reset
    func resetToDefaults() {
        bassAttenuation = 30.0
    }
}
