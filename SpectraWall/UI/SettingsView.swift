//
//  SettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var settings = AppSettings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: - Header
            HStack {
                Text("SpectraWall")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // MARK: - 音訊來源
            SectionHeader(title: "音訊來源")

            VStack(alignment: .leading, spacing: 6) {
                AudioSourceRow(
                    title: "Global（所有音訊）",
                    isSelected: settings.audioSource == .global,
                    isDisabled: false
                ) {
                    settings.audioSource = .global
                }

                ForEach(settings.activeApps, id: \.pid) { app in
                    AudioSourceRow(
                        title: app.name,
                        isSelected: settings.audioSource == .app(app),
                        isDisabled: false
                    ) {
                        settings.audioSource = .app(app)
                    }
                }

                if case .app(let selectedApp) = settings.audioSource,
                   !settings.activeApps.contains(where: { $0.pid == selectedApp.pid }) {
                    AudioSourceRow(
                        title: selectedApp.name,
                        isSelected: true,
                        isDisabled: true
                    ) {}
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // MARK: - 底部按鈕
            HStack {
                Button("設定") {
                    AppWindowManager.shared.openSettings()
                }
                .buttonStyle(.plain)
                .font(.caption)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 240)
    }
}
