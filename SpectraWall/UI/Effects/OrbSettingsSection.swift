//
//  OrbSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

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
                SettingsSlider(label: "Blob", value: $settings.blobAmount, spec: OrbSpec.blobAmount)
                SettingsSlider(label: "Hue Cycle", value: $settings.hueCycleSpeed, spec: OrbSpec.hueCycleSpeed)
            }

            // MARK: - Ripple
            SettingsCard(title: "Ripple") {
                Toggle("Enable Ripple", isOn: $settings.rippleEnabled)
                SettingsSlider(label: "Threshold", value: $settings.rippleThreshold, spec: OrbSpec.rippleThreshold)
                    .disabled(!settings.rippleEnabled)
                SettingsSlider(label: "Speed", value: $settings.rippleSpeed, spec: OrbSpec.rippleSpeed)
                    .disabled(!settings.rippleEnabled)
                SettingsSlider(label: "Opacity", value: $settings.rippleOpacity, spec: OrbSpec.rippleOpacity)
                    .disabled(!settings.rippleEnabled)
                SettingsSlider(label: "Duration", value: $settings.rippleDuration, spec: OrbSpec.rippleDuration)
                    .disabled(!settings.rippleEnabled)
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
        .syncEffectSettings($settings, layer: layer) { preRandomizeSnapshot = nil }
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
