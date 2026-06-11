//
//  AmbientGlowSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/6/11.
//

import SwiftUI

struct AmbientGlowSettingsSection: View {
    @ObservedObject var layer: LayerSettings
    @State private var settings: AmbientGlowSettings = .defaults
    @State private var preRandomizeSnapshot: AmbientGlowSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(title: "Glow", accessory: {
                RandomizeControls(
                    canUndo: preRandomizeSnapshot != nil,
                    onRandomize: randomize,
                    onUndo: restore
                )
            }) {
                Picker("Placement", selection: $settings.placement) {
                    ForEach(GlowPlacement.allCases, id: \.self) { placement in
                        Text(placement.localized).tag(placement)
                    }
                }
                .pickerStyle(.segmented)

                SettingsSlider(label: "Size", value: $settings.size, spec: AmbientGlowSpec.size)
                SettingsSlider(label: "Intensity", value: $settings.intensity, spec: AmbientGlowSpec.intensity)

                Divider()

                SettingsSlider(label: "Attack", value: $settings.attack, spec: AmbientGlowSpec.attack)
                SettingsSlider(label: "Release", value: $settings.release, spec: AmbientGlowSpec.release)
            }

            SettingsCard(title: "Color") {
                ColorPickerRow(label: "Low Amplitude", colorData: $settings.colorLow)
                ColorPickerRow(label: "High Amplitude", colorData: $settings.colorHigh)
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
