//
//  VisualizerSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI
import Combine
import ServiceManagement

class VisualizerSettings: ObservableObject {
    static let shared = VisualizerSettings()

    // MARK: - 公用（Analyzer 層）
    @AppStorage("bassAttenuation") var bassAttenuation: Double = 30.0

    // MARK: - Reset
    func resetToDefaults() {
        bassAttenuation = 30.0
    }
}

extension VisualizerSettings {
    var launchAtLogin: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("LaunchAtLogin error: \(error)")
            }
        }
    }
}
