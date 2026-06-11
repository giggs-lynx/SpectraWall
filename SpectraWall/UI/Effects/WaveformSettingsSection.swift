//
//  WaveformSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/6/11.
//

import SwiftUI

struct WaveformSettingsSection: View {
    @ObservedObject var layer: LayerSettings
    @State private var settings: WaveformSettings = .defaults
    @State private var preRandomizeSnapshot: WaveformSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(title: "Waveform", accessory: {
                RandomizeControls(
                    canUndo: preRandomizeSnapshot != nil,
                    onRandomize: randomize,
                    onUndo: restore
                )
            }) {
                SettingsSlider(label: "Window", value: $settings.windowSeconds, spec: WaveformSpec.windowSeconds)
                SettingsSlider(label: "Height", value: $settings.gain, spec: WaveformSpec.gain)
                SettingsSlider(label: "Max Height", value: $settings.maxHeight, spec: WaveformSpec.maxHeight)
            }

            SettingsCard(title: "Color") {
                ChannelColorSettingsView(colorSettings: $settings.colorSettings)
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
