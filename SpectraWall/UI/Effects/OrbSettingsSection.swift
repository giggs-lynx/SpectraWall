//
//  OrbSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI
import Combine

struct OrbSettingsSection: View {
    @ObservedObject var layer: LayerSettings
    @State private var settings: OrbSettings = .defaults

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(title: "Orb") {
                // MARK: - Audio Dynamics
                SettingsSlider(label: "Sensitivity", value: $settings.boost, range: 1.0...6.0, step: 0.1)
                SettingsSlider(label: "Attack", value: $settings.attack, range: 0.3...1.0, step: 0.05)
                SettingsSlider(label: "Release", value: $settings.release, range: 0.1...0.5, step: 0.05)

                Divider()

                // MARK: - Geometric Settings
                SettingsSlider(label: "Base Radius", value: $settings.baseRadius, range: 40...300, step: 5)
                SettingsSlider(
                    label: "Outer Radius Multiplier",
                    value: $settings.outerRadiusMultiplier,
                    range: 1.0...3.0,
                    step: 0.1
                )
            }

            // MARK: - Appearance: Inner
            SettingsCard(title: "Inner Color") {
                ColorPickerRow(label: "Low Frequency", colorData: $settings.innerColorLow)
                ColorPickerRow(label: "High Frequency", colorData: $settings.innerColorHigh)
            }

            // MARK: - Appearance: Outer
            SettingsCard(title: "Outer Color") {
                ColorPickerRow(label: "Low Frequency", colorData: $settings.outerColorLow)
                ColorPickerRow(label: "High Frequency", colorData: $settings.outerColorHigh)
                SettingsSlider(label: "Outer Opacity", value: $settings.outerOpacity, range: 0.0...1.0, step: 0.05)
            }
        }
        .onAppear {
            if let orbSettings = layer.effectSettings as? OrbSettings {
                settings = orbSettings
            }
        }
        .onChange(of: layer.id) { _, _ in
            if let orbSettings = layer.effectSettings as? OrbSettings {
                settings = orbSettings
            }
        }
        .onChange(of: settings) { _, newValue in
            if let current = layer.effectSettings as? OrbSettings, current == newValue {
                return
            }
            layer.effectSettings = newValue
            VisualizerSceneManager.shared.save()
        }
        .onReceive(layer.objectWillChange) { _ in
            if let orbSettings = layer.effectSettings as? OrbSettings,
               orbSettings != settings {
                settings = orbSettings
            }
        }
    }
}
