//
//  SpectrumSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

struct SpectrumSettingsSection: View {
    @ObservedObject var layer: LayerSettings
    @State private var settings: SpectrumSettings = .defaults
    @State private var preRandomizeSnapshot: SpectrumSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCard(title: "Spectrum", accessory: {
                RandomizeControls(
                    canUndo: preRandomizeSnapshot != nil,
                    onRandomize: randomize,
                    onUndo: restore
                )
            }) {
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

                Toggle("Mirror", isOn: $settings.mirror)
                    .onChange(of: settings.mirror) { _, mirrored in
                        applyMirrorPosition(mirrored)
                    }

                // MARK: - Dimension Settings
                SettingsSlider(label: "Height", value: $settings.gain, spec: SpectrumSpec.gain)
                SettingsSlider(label: "Max Height", value: $settings.maxHeight, spec: SpectrumSpec.maxHeight)
                SettingsSlider(label: "Width", value: $settings.width, spec: SpectrumSpec.width)

                Divider()

                // MARK: - Audio Dynamics
                SettingsSlider(label: "Dynamics", value: $settings.powerCurve, spec: SpectrumSpec.powerCurve)
                SettingsSlider(label: "Attack", value: $settings.attack, spec: SpectrumSpec.attack)
                SettingsSlider(label: "Release", value: $settings.release, spec: SpectrumSpec.release)
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
        if settings.mirror {
            centerAmpAxis(for: anchor)
        }
        VisualizerSceneManager.shared.save()
    }

    // Mirrored bars grow both ways from the base line; an edge-snapped base
    // would clip one half off-screen, so snap the amplitude axis to center.
    // Turning mirror off snaps back to the anchor's edge position.
    private func applyMirrorPosition(_ mirrored: Bool) {
        if mirrored {
            centerAmpAxis(for: settings.anchor)
            VisualizerSceneManager.shared.save()
        } else {
            applyAnchorPosition(settings.anchor)
        }
    }

    private func centerAmpAxis(for anchor: SpectrumAnchor) {
        switch anchor {
        case .bottom, .top: layer.positionY = 0.5
        case .left, .right: layer.positionX = 0.5
        }
    }
}
