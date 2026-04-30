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

    var body: some View {
        SectionHeader(title: "Orb")
        VStack(spacing: 10) {
            SettingsSlider(label: "Sensitivity", value: $settings.boost, range: 1.0...6.0, step: 0.1)
            SettingsSlider(label: "Attack", value: $settings.attack, range: 0.3...1.0, step: 0.05)
            SettingsSlider(label: "Release", value: $settings.release, range: 0.1...0.5, step: 0.05)
            SettingsSlider(label: "Base Radius", value: $settings.baseRadius, range: 40...300, step: 5)
            SettingsSlider(label: "Outer Radius Multiplier", value: $settings.outerRadiusMultiplier, range: 1.0...3.0, step: 0.1)

            Divider()

            SectionHeader(title: "Inner Color")
            ColorPickerRow(label: "Low Frequency", colorData: $settings.innerColorLow)
            ColorPickerRow(label: "High Frequency", colorData: $settings.innerColorHigh)

            Divider()

            SectionHeader(title: "Outer Color")
            ColorPickerRow(label: "Low Frequency", colorData: $settings.outerColorLow)
            ColorPickerRow(label: "High Frequency", colorData: $settings.outerColorHigh)
            SettingsSlider(label: "Outer Opacity", value: $settings.outerOpacity, range: 0.0...1.0, step: 0.05)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onAppear {
            settings = layer.effectSettings as? OrbSettings ?? .defaults
        }
        .onChange(of: settings) { _, newValue in
            layer.effectSettings = newValue
            VisualizerSceneManager.shared.save()
        }

        Divider()
    }
}
