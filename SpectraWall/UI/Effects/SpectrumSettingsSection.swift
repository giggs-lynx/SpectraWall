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

    var body: some View {
        SectionHeader(title: "Spectrum")
        VStack(spacing: 10) {
            Picker("Anchor", selection: $settings.anchor) {
                ForEach(SpectrumAnchor.allCases, id: \.self) { anchor in
                    Text(anchor.localized).tag(anchor)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.anchor) { _, newAnchor in
                switch newAnchor {
                case .bottom:
                    layer.positionY = 0.0
                    layer.positionX = 0.5
                case .top:
                    layer.positionY = 1.0
                    layer.positionX = 0.5
                case .left:
                    layer.positionX = 0.0
                    layer.positionY = 0.5
                case .right:
                    layer.positionX = 1.0
                    layer.positionY = 0.5
                }
                VisualizerSceneManager.shared.save()
            }

            SettingsSlider(label: "Height", value: $settings.gain, range: 0.5...3.0, step: 0.1)
            SettingsSlider(label: "Max Height", value: $settings.maxHeight, range: 0.1...1.0, step: 0.05)
            SettingsSlider(label: "Width", value: $settings.width, range: 0.1...1.0, step: 0.05)
            SettingsSlider(label: "Dynamics", value: $settings.powerCurve, range: 1.0...3.0, step: 0.1)
            SettingsSlider(label: "Attack", value: $settings.attack, range: 0.5...1.0, step: 0.05)
            SettingsSlider(label: "Release", value: $settings.release, range: 0.1...0.5, step: 0.05)

            Divider()

            if layer.channelMode == .stereo {
                Toggle("Sync Colors", isOn: $settings.colorSync)

                if settings.colorSync {
                    ChannelColorSettingsView(colorSettings: $settings.colorSettings)
                } else {
                    SectionHeader(title: "Left Channel")
                    ChannelColorSettingsView(colorSettings: $settings.leftColorSettings)
                    SectionHeader(title: "Right Channel")
                    ChannelColorSettingsView(colorSettings: $settings.rightColorSettings)
                }
            } else {
                ChannelColorSettingsView(colorSettings: $settings.colorSettings)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onAppear {
            settings = layer.effectSettings as? SpectrumSettings ?? .defaults
        }
        .onChange(of: settings) { _, newValue in
            layer.effectSettings = newValue
            VisualizerSceneManager.shared.save()
        }

        Divider()
    }
}
