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

    @AppStorage("attackCoeff") var attackCoeff: Double = 0.95
    @AppStorage("releaseCoeff") var releaseCoeff: Double = 0.2
    @AppStorage("gain") var gain: Double = 1.8
    @AppStorage("powerCurve") var powerCurve: Double = 1.5
    @AppStorage("bassAttenuation") var bassAttenuation: Double = 30.0
    
    
    func resetToDefaults() {
        attackCoeff = 0.95
        releaseCoeff = 0.2
        gain = 1.8
        powerCurve = 1.5
        bassAttenuation = 30.0
    }
}
