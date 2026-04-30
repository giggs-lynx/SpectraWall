//
//  VisualizerSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI
import Combine
import ServiceManagement
import os.log

class VisualizerSettings: ObservableObject {
    static let shared = VisualizerSettings()
    
    private let logger = Logger(subsystem: AppConstants.bundleId, category: "VisualizerSettings")
    
    @AppStorage("bassAttenuation") var bassAttenuation: Double = 30.0
    
    private init() {}

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
                objectWillChange.send()
            } catch {
                logger.error("LaunchAtLogin error: \(error.localizedDescription)")
            }
        }
    }
}
