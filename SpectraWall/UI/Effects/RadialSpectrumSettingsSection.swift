//
//  RadialSpectrumSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/6/11.
//

import SwiftUI

struct RadialSpectrumSettingsSection: View {
    @ObservedObject var layer: LayerSettings
    @State private var settings: RadialSpectrumSettings = .defaults
    @State private var preRandomizeSnapshot: RadialSpectrumSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(title: "Radial", accessory: {
                RandomizeControls(
                    canUndo: preRandomizeSnapshot != nil,
                    onRandomize: randomize,
                    onUndo: restore
                )
            }) {
                // MARK: - Geometry
                SettingsSlider(label: "Inner Radius", value: $settings.innerRadius, spec: RadialSpectrumSpec.innerRadius)
                SettingsSlider(label: "Max Extent", value: $settings.maxExtent, spec: RadialSpectrumSpec.maxExtent)
                SettingsSlider(label: "Height", value: $settings.gain, spec: RadialSpectrumSpec.gain)

                Toggle("Mirror", isOn: $settings.mirror)

                Divider()

                // MARK: - Audio Dynamics
                SettingsSlider(label: "Dynamics", value: $settings.powerCurve, spec: RadialSpectrumSpec.powerCurve)
                SettingsSlider(label: "Attack", value: $settings.attack, spec: RadialSpectrumSpec.attack)
                SettingsSlider(label: "Release", value: $settings.release, spec: RadialSpectrumSpec.release)
            }

            // MARK: - Appearance & Color
            colorSettingsSection
        }
        .syncEffectSettings($settings, layer: layer) { preRandomizeSnapshot = nil }
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
