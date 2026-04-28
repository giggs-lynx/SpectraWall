//
//  SettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var sceneManager = VisualizerSceneManager.shared
    @State private var sceneHoveredID: UUID? = nil
    @State private var footerHovered: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SpectraWall")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

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

            SectionHeader(title: "場景")

            VStack(alignment: .leading, spacing: 6) {
                ForEach(sceneManager.scenes) { scene in
                    let isActive = sceneManager.activeSceneID == scene.id
                    HStack(spacing: 8) {
                        Image(systemName: isActive ? "circle.fill" : "circle")
                            .foregroundColor(isActive ? .accentColor : .secondary)
                            .frame(width: 16)

                        Text(scene.name)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(sceneHoveredID == scene.id ? Color.primary.opacity(0.08) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        sceneManager.setActiveScene(scene)
                    }
                    .onHover { hovering in
                        sceneHoveredID = hovering ? scene.id : nil
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text("設定")
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(footerHovered == "settings" ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    AppWindowManager.shared.openSettings()
                }
                .onHover { hovering in
                    footerHovered = hovering ? "settings" : nil
                }

                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text("結束 SpectraWall")
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(footerHovered == "quit" ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    NSApplication.shared.terminate(nil)
                }
                .onHover { hovering in
                    footerHovered = hovering ? "quit" : nil
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 240)
    }
}
