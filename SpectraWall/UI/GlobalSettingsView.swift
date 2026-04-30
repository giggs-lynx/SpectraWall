//
//  GlobalSettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI
import ServiceManagement
import os

struct GlobalSettingsView: View {
    @ObservedObject var visualizerSettings = VisualizerSettings.shared
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    
    private let logger = Logger(subsystem: AppConstants.bundleId, category: "GlobalSettingsView")
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "System")
                VStack(spacing: 10) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) {
                            do {
                                if launchAtLogin {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                logger.error("LaunchAtLogin error: \(error)")
                                // Restore UI on failure
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                Divider()
                
                SectionHeader(title: "Audio")
                VStack(spacing: 10) {
                    SettingsSlider(
                        label: "Bass Suppression",
                        value: $visualizerSettings.bassAttenuation,
                        range: 0...40,
                        step: 1
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                Divider()

                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        visualizerSettings.resetToDefaults()
                    }
                    .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 16)
            }
        }
    }
}
