//
//  PopoverView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var sceneManager = VisualizerSceneManager.shared
    @State private var aboutHovered = false
    
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(AppConstants.appName)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 12)
            .background(aboutHovered ? Hover.fill : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .showAboutWindow, object: nil)
            }
            .onHover { aboutHovered = $0 }
            .help("About SpectraWall")

            Divider()

            SectionHeader(title: "Audio Source", imageName: "audio_tap")

            VStack(alignment: .leading, spacing: 6) {
                AudioSourceRow(
                    title: String(localized: "System Audio"),
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

            SectionHeader(title: "Scenes", systemImageName: "square.stack", imageColor: .purple)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(sceneManager.scenes) { scene in
                    let isActive = sceneManager.activeScene === scene
                    HoverableRow {
                        sceneManager.setActiveScene(scene)
                    } content: {
                        HStack(spacing: 8) {
                            Image(systemName: isActive ? "circle.fill" : "circle")
                                .foregroundColor(isActive ? .accentColor : .secondary)
                                .frame(width: 16)

                            Text(scene.name)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HoverableRow {
                    openSettings()
                    DispatchQueue.main.async {
                        if let win = NSApp.windows.first(where: {
                            $0.identifier?.rawValue.lowercased().contains("settings") == true
                        }) {
                            win.collectionBehavior.insert(.moveToActiveSpace)
                            win.makeKeyAndOrderFront(nil)
                        }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                } content: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.orange)
                            .frame(width: 16)
                        Text("Settings")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }

                HoverableRow {
                    NSApplication.shared.terminate(nil)
                } content: {
                    HStack(spacing: 8) {
                        Image(systemName: "power")
                            .foregroundColor(.red)
                            .frame(width: 16)
                        Text("Quit SpectraWall")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 8)
        }
        .frame(width: 240)
    }
}
