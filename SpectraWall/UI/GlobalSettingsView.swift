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
    @ObservedObject var visualizerSettings = VisualizerSettings.shared
    @ObservedObject var appSettings = AppSettings.shared
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var screens: [NSScreen] = NSScreen.screens

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
                                AppLog.lifecycle.error("LaunchAtLogin error: \(error)")
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                Divider()

                SectionHeader(title: "Displays", systemImageName: "display", imageColor: .blue)
                VStack(spacing: 10) {
                    ForEach(screens, id: \.displayID) { screen in
                        Toggle(screen.localizedName, isOn: screenToggleBinding(for: screen))
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

                SectionHeader(title: "Motion")
                VStack(spacing: 10) {
                    Picker("Animation Style", selection: $appSettings.motionStyle) {
                        ForEach(MotionStyle.allCases, id: \.self) { style in
                            Text(style.localized).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
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
