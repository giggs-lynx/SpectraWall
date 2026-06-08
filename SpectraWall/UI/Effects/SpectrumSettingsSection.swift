//
//  SpectrumSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI
import Combine

struct SpectrumSettingsSection: View {
    @ObservedObject var layer: LayerSettings
    @State private var settings: SpectrumSettings = .defaults

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(title: "Spectrum") {
                // MARK: - Layout & Anchor
                Picker("Anchor", selection: $settings.anchor) {
                    ForEach(SpectrumAnchor.allCases, id: \.self) { anchor in
                        Text(anchor.localized).tag(anchor)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.anchor) { _, newAnchor in
                    applyAnchorPosition(newAnchor)
                }

                // MARK: - Dimension Settings
                SettingsSlider(label: "Height", value: $settings.gain, range: 0.5...3.0, step: 0.1)
                SettingsSlider(label: "Max Height", value: $settings.maxHeight, range: 0.1...1.0, step: 0.05)
                SettingsSlider(label: "Width", value: $settings.width, range: 0.1...1.0, step: 0.05)

                Divider()

                // MARK: - Audio Dynamics
                SettingsSlider(label: "Dynamics", value: $settings.powerCurve, range: 1.0...3.0, step: 0.1)
                SettingsSlider(label: "Attack", value: $settings.attack, range: 0.5...1.0, step: 0.05)
                SettingsSlider(label: "Release", value: $settings.release, range: 0.1...0.5, step: 0.05)
            }

            // MARK: - Appearance & Color
            colorSettingsSection
        }
        .onAppear {
            if let spectrumSettings = layer.effectSettings as? SpectrumSettings {
                settings = spectrumSettings
            }
        }
        .onChange(of: layer.id) { _, _ in
            // Re-sync when this section is reused for a different layer
            // (we removed `.id(layer.id)` to avoid expensive ColorPicker rebuilds).
            if let spectrumSettings = layer.effectSettings as? SpectrumSettings {
                settings = spectrumSettings
            }
        }
        .onChange(of: settings) { _, newValue in
            // Skip write-back when value already matches (avoids onAppear → onChange
            // feedback loop firing layer.objectWillChange on every layer switch).
            if let current = layer.effectSettings as? SpectrumSettings, current == newValue {
                return
            }
            layer.effectSettings = newValue
            VisualizerSceneManager.shared.save()
        }
        .onReceive(layer.objectWillChange) { _ in
            if let spectrumSettings = layer.effectSettings as? SpectrumSettings,
               spectrumSettings != settings {
                settings = spectrumSettings
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var colorSettingsSection: some View {
        if layer.channelMode == .stereo {
            SettingsCard(title: "Color") {
                Toggle("Sync Colors", isOn: $settings.colorSync)
                if settings.colorSync {
                    ChannelColorSettingsView(colorSettings: $settings.colorSettings)
                }
            }

            if !settings.colorSync {
                SettingsCard(title: "Left Channel") {
                    ChannelColorSettingsView(colorSettings: $settings.leftColorSettings)
                }
                SettingsCard(title: "Right Channel") {
                    ChannelColorSettingsView(colorSettings: $settings.rightColorSettings)
                }
            }
        } else {
            SettingsCard(title: "Color") {
                ChannelColorSettingsView(colorSettings: $settings.colorSettings)
            }
        }
    }

    // MARK: - Helper Functions

    private func applyAnchorPosition(_ anchor: SpectrumAnchor) {
        // Encapsulate coordinate logic to keep onChange clean
        switch anchor {
        case .bottom:
            layer.positionX = 0.5
            layer.positionY = 0.0
        case .top:
            layer.positionX = 0.5
            layer.positionY = 1.0
        case .left:
            layer.positionX = 0.0
            layer.positionY = 0.5
        case .right:
            layer.positionX = 1.0
            layer.positionY = 0.5
        }
        VisualizerSceneManager.shared.save()
    }
}
