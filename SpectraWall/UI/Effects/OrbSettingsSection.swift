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
    @State private var preRandomizeSnapshot: OrbSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(title: "Orb", accessory: {
                RandomizeControls(
                    canUndo: preRandomizeSnapshot != nil,
                    onRandomize: randomize,
                    onUndo: restore
                )
            }) {
                // MARK: - Audio Dynamics
                SettingsSlider(label: "Sensitivity", value: $settings.boost, spec: OrbSpec.boost)
                SettingsSlider(label: "Attack", value: $settings.attack, spec: OrbSpec.attack)
                SettingsSlider(label: "Release", value: $settings.release, spec: OrbSpec.release)

                Divider()

                // MARK: - Geometric Settings
                SettingsSlider(label: "Base Radius", value: $settings.baseRadius, spec: OrbSpec.baseRadius)
                SettingsSlider(
                    label: "Outer Radius Multiplier",
                    value: $settings.outerRadiusMultiplier,
                    spec: OrbSpec.outerRadiusMultiplier
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
                SettingsSlider(label: "Outer Opacity", value: $settings.outerOpacity, spec: OrbSpec.outerOpacity)
            }
        }
        .onAppear {
            if let orbSettings = layer.effectSettings as? OrbSettings {
                settings = orbSettings
            }
        }
        .onChange(of: layer.id) { _, _ in
            preRandomizeSnapshot = nil
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

    // MARK: - Randomize

    private func randomize() {
        preRandomizeSnapshot = settings
        settings = settings.randomized()
    }

    private func restore() {
        guard let snapshot = preRandomizeSnapshot else { return }
        settings = snapshot
        preRandomizeSnapshot = nil
    }
}
