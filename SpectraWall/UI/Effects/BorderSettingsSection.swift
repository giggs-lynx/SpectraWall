//
//  BorderSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

struct BorderSettingsSection: View {
    @ObservedObject var layer: LayerSettings
    @State private var settings: BorderSettings = .defaults
    @State private var preRandomizeSnapshot: BorderSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(title: "Border", accessory: {
                RandomizeControls(
                    canUndo: preRandomizeSnapshot != nil,
                    onRandomize: randomize,
                    onUndo: restore
                )
            }) {
                // MARK: - Animation Control
                HStack {
                    Picker("Stroke Count", selection: $settings.strokeCount) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Clockwise", isOn: $settings.clockwise)
                        .toggleStyle(.button)
                }

                // MARK: - Geometric Settings
                SettingsSlider(label: "Speed", value: $settings.speed, spec: BorderSpec.speed)
                SettingsSlider(label: "Tail Length", value: $settings.tailLength, spec: BorderSpec.tailLength)
                SettingsSlider(label: "Line Width", value: $settings.baseWidth, spec: BorderSpec.baseWidth)
                SettingsSlider(label: "Corner Radius", value: $settings.cornerRadius, spec: BorderSpec.cornerRadius)

                Divider()

                // MARK: - Audio Response & Trail Flash
                SettingsSlider(label: "Pulse Attack", value: $settings.pulseAttack, spec: BorderSpec.pulseAttack)
                SettingsSlider(label: "Pulse Release", value: $settings.pulseRelease, spec: BorderSpec.pulseRelease)
                SettingsSlider(label: "Pulse Flash", value: $settings.pulseFlash, spec: BorderSpec.pulseFlash)
                SettingsSlider(label: "Beat Speed Boost", value: $settings.pulseSpeedBoost, spec: BorderSpec.pulseSpeedBoost)
                SettingsSlider(label: "Width Breath", value: $settings.widthBreath, spec: BorderSpec.widthBreath)

                Divider()

                // MARK: - Ghost
                Toggle("Enable Ghost", isOn: $settings.ghostEnabled)
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if settings.ghostEnabled {
                    SettingsSlider(label: "Ghost Size", value: $settings.ghostSize, spec: BorderSpec.ghostSize)
                    SettingsSlider(label: "Ghost Opacity", value: $settings.ghostOpacity, spec: BorderSpec.ghostOpacity)
                    SettingsSlider(label: "Ghost Decay", value: $settings.ghostDecay, spec: BorderSpec.ghostDecay)
                }
            }

            // MARK: - Appearance
            strokeColorSettings
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

    @ViewBuilder
    private var strokeColorSettings: some View {
        SettingsCard(title: "First Stroke") {
            ColorPickerRow(label: "Head", colorData: $settings.stroke1ColorStart)
            ColorPickerRow(label: "Tail", colorData: $settings.stroke1ColorEnd)
        }

        if settings.strokeCount == 2 {
            SettingsCard(title: "Second Stroke") {
                ColorPickerRow(label: "Head", colorData: $settings.stroke2ColorStart)
                ColorPickerRow(label: "Tail", colorData: $settings.stroke2ColorEnd)
            }
        }
    }
}
