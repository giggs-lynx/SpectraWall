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

    // MARK: - Spectrum 專屬
    @AppStorage("spectrumGain") var spectrumGain: Double = 1.8
    @AppStorage("spectrumAttack") var spectrumAttack: Double = 0.95
    @AppStorage("spectrumRelease") var spectrumRelease: Double = 0.2
    @AppStorage("spectrumPowerCurve") var spectrumPowerCurve: Double = 1.5

    // MARK: - Orb 專屬
    @AppStorage("orbBoost") var orbBoost: Double = 3.0
    @AppStorage("orbAttack") var orbAttack: Double = 0.6
    @AppStorage("orbRelease") var orbRelease: Double = 0.25

    // MARK: - Reset
    func resetToDefaults() {
        bassAttenuation = 30.0
        spectrumGain = 1.8
        spectrumAttack = 0.95
        spectrumRelease = 0.2
        spectrumPowerCurve = 1.5
        orbBoost = 3.0
        orbAttack = 0.6
        orbRelease = 0.25
    }
}
