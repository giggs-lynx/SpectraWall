//
//  SettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var visualizerSettings = VisualizerSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SpectraWall")
                .font(.headline)

            Divider()

            Text("音訊來源")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                // Global 選項
                AudioSourceRow(title: "Global（所有音訊）", isSelected: settings.audioSource == .global, isDisabled: false) {
                    settings.audioSource = .global
                }

                // 動態 app 列表
                ForEach(settings.activeApps, id: \.pid) { app in
                    AudioSourceRow(
                        title: app.name,
                        isSelected: settings.audioSource == .app(app),
                        isDisabled: false
                    ) {
                        settings.audioSource = .app(app)
                    }
                }

                // 如果選中的 app 不在 activeApps 裡，顯示 grey out
                if case .app(let selectedApp) = settings.audioSource,
                   !settings.activeApps.contains(where: { $0.pid == selectedApp.pid }) {
                    AudioSourceRow(
                        title: selectedApp.name,
                        isSelected: true,
                        isDisabled: true  // grey out
                    ) {}
                }
            }

            Divider()
            
            Section {
                Text("視覺化設定")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                SettingsSlider(
                    label: "整體高度",
                    value: $visualizerSettings.gain,
                    range: 0.5...3.0,
                    step: 0.1
                )

                SettingsSlider(
                    label: "差異化",
                    value: $visualizerSettings.powerCurve,
                    range: 1.0...3.0,
                    step: 0.1
                )

                SettingsSlider(
                    label: "反應速度",
                    value: $visualizerSettings.attackCoeff,
                    range: 0.5...1.0,
                    step: 0.05
                )

                SettingsSlider(
                    label: "衰減速度",
                    value: $visualizerSettings.releaseCoeff,
                    range: 0.1...0.5,
                    step: 0.05
                )

                SettingsSlider(
                    label: "低頻壓制",
                    value: $visualizerSettings.bassAttenuation,
                    range: 0...40,
                    step: 1
                )
                
                HStack {
                    Text("視覺化設定")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("恢復預設值") {
                        visualizerSettings.resetToDefaults()
                    }
                    .font(.caption)
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundColor(.red)
        }
        .padding(16)
        .frame(width: 260)
    }
}

struct AudioSourceRow: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDisabled ? .secondary : (isSelected ? .accentColor : .secondary))
                Text(title)
                    .foregroundColor(isDisabled ? .secondary : .primary)
                if isDisabled {
                    Spacer()
                    Text("無音訊")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct SettingsSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
