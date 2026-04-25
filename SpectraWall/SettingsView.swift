//
//  SettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

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
