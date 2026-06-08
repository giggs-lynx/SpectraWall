//
//  CommonSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI
import Combine

struct CommonSettingsSection: View {
    @ObservedObject var layer: LayerSettings

    @State private var channelMode: ChannelMode = .stereo
    @State private var opacity: Double = 1.0
    @State private var positionX: Double = 0.5
    @State private var positionY: Double = 0.0

    /// Which sub-controls to expose, looked up from the effect's descriptor.
    /// Defaults to `.all` if the effect type isn't registered yet (shouldn't
    /// happen at runtime, but keeps SwiftUI previews happy).
    private var visible: CommonSettings {
        EffectRegistry.descriptor(for: layer.effectType)?.commonSettings ?? .all
    }

    var body: some View {
        SettingsCard(title: "General") {
            // MARK: - Audio Configuration
            if visible.contains(.channelMode) {
                Picker("Channel", selection: $channelMode) {
                    ForEach(ChannelMode.allCases, id: \.self) { mode in
                        Text(mode.localized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            let hasTransform = visible.contains(.opacity) || visible.contains(.position)
            if visible.contains(.channelMode), hasTransform {
                Divider()
            }

            // MARK: - Transform & Opacity
            if visible.contains(.opacity) {
                SettingsSlider(label: "Opacity", value: $opacity, range: 0.0...1.0, step: 0.05)
            }
            if visible.contains(.position) {
                SettingsSlider(label: "Position X", value: $positionX, range: 0.0...1.0, step: 0.01)
                SettingsSlider(label: "Position Y", value: $positionY, range: 0.0...1.0, step: 0.01)
            }
        }
        .onAppear {
            channelMode = layer.channelMode
            opacity = layer.opacity
            positionX = layer.positionX
            positionY = layer.positionY
        }
        .onChange(of: layer.id) { _, _ in
            // Re-sync @State when the view is reused for a different layer.
            // Required because we removed `.id(layer.id)` to avoid the
            // expensive full rebuild (multiple ColorPickers reinstantiating)
            // on every layer switch.
            channelMode = layer.channelMode
            opacity = layer.opacity
            positionX = layer.positionX
            positionY = layer.positionY
        }
        // MARK: - State Sync & Persistence
        // Guards prevent the onAppear → onChange feedback loop where SwiftUI fires
        // onChange after onAppear assigns @State, causing a no-op write-back that
        // still triggers layer.objectWillChange and cascades to every effect node.
        .onChange(of: channelMode) { _, newValue in
            guard layer.channelMode != newValue else { return }
            layer.channelMode = newValue
            VisualizerSceneManager.shared.save()
        }
        .onChange(of: opacity) { _, newValue in
            guard layer.opacity != newValue else { return }
            layer.opacity = newValue
            VisualizerSceneManager.shared.save()
        }
        .onChange(of: positionX) { _, newValue in
            guard layer.positionX != newValue else { return }
            layer.positionX = newValue
            VisualizerSceneManager.shared.save()
        }
        .onChange(of: positionY) { _, newValue in
            guard layer.positionY != newValue else { return }
            layer.positionY = newValue
            VisualizerSceneManager.shared.save()
        }
        .onReceive(layer.objectWillChange) { _ in
            opacity = layer.opacity
            positionX = layer.positionX
            positionY = layer.positionY
            channelMode = layer.channelMode
        }
    }
}
