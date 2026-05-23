//
//  AnalyzerSettings.swift
//  SpectraWall
//
//  Persistent knobs that affect the audio analyzer (currently only the bass
//  attenuation curve applied during dB → bar normalisation). Lives in
//  UserDefaults via @AppStorage, separate from AppConfig because it's a
//  single-key preference rather than a structured config blob.
//

import Combine
import SwiftUI

class AnalyzerSettings: ObservableObject {
    static let shared = AnalyzerSettings()

    @AppStorage("bassAttenuation") var bassAttenuation: Double = 30.0

    private init() {}

    func resetToDefaults() {
        bassAttenuation = 30.0
    }
}
