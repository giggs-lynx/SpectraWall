//
//  GlobalSettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI
import ServiceManagement

struct GlobalSettingsView: View {
    @ObservedObject var visualizerSettings = VisualizerSettings.shared
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "系統")
                VStack(spacing: 10) {
                    Toggle("登入時自動啟動", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) {
                            do {
                                if launchAtLogin {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("LaunchAtLogin error: \(error)")
                                // 失敗時還原 UI
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                Divider()
                
                SectionHeader(title: "音訊分析")
                VStack(spacing: 10) {
                    SettingsSlider(
                        label: "低頻壓制",
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
                    Button("恢復預設值") {
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
