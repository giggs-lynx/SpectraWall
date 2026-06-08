//
//  GlobalSettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI
import ServiceManagement
import OSLog

struct GlobalSettingsView: View {
    @ObservedObject var visualizerSettings = AnalyzerSettings.shared
    @ObservedObject var appSettings = AppSettings.shared
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var screens: [NSScreen] = NSScreen.screens

    var body: some View {
        Form {
            Section("System") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do {
                            if launchAtLogin {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            AppLog.lifecycle.error("LaunchAtLogin error: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Displays") {
                ForEach(screens, id: \.displayID) { screen in
                    Toggle(screen.localizedName, isOn: screenToggleBinding(for: screen))
                }
            }

            Section("Audio") {
                SettingsSlider(
                    label: "Bass Suppression",
                    value: $visualizerSettings.bassAttenuation,
                    range: 0...40,
                    step: 1,
                    unit: "dB"
                )
            }

            Section("Motion") {
                Picker("Animation Style", selection: $appSettings.motionStyle) {
                    ForEach(MotionStyle.allCases, id: \.self) { style in
                        Text(style.localized).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Rendering") {
                Toggle("Anti-aliasing (MSAA 4×)", isOn: $appSettings.msaaEnabled)
            }

            Section("Debug") {
                Toggle("Debug Overlay (geometry skeleton)", isOn: $appSettings.debugEnabled)
            }

            Section {
                Button("Reset to Defaults") {
                    visualizerSettings.resetToDefaults()
                }
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            screens = NSScreen.screens
        }
    }

    private func screenToggleBinding(for screen: NSScreen) -> Binding<Bool> {
        let id = screen.displayID
        return Binding(
            get: { appSettings.enabledDisplayIDs.contains(id) },
            set: { isOn in
                if isOn {
                    appSettings.enabledDisplayIDs.insert(id)
                } else {
                    appSettings.enabledDisplayIDs.remove(id)
                }
            }
        )
    }
}
