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
    @State private var sceneHoveredID: UUID?
    @State private var footerHovered: String?
    
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(footerHovered == "about" ? Color.primary.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .showAboutWindow, object: nil)
            }
            .onHover { hovering in
                footerHovered = hovering ? "about" : nil
            }
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

            VStack(alignment: .leading, spacing: 6) {
                ForEach(sceneManager.scenes) { scene in
                    let isActive = sceneManager.activeScene === scene
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
                        .foregroundColor(.orange)
                        .frame(width: 16)
                    Text("Settings")
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
                }
                .onHover { hovering in
                    footerHovered = hovering ? "settings" : nil
                }

                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .foregroundColor(.red)
                        .frame(width: 16)
                    Text("Quit SpectraWall")
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
