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

            // MARK: - Dimension Settings
            SettingsSlider(label: "Height", value: $settings.gain, range: 0.5...3.0, step: 0.1)
            SettingsSlider(label: "Max Height", value: $settings.maxHeight, range: 0.1...1.0, step: 0.05)
            SettingsSlider(label: "Width", value: $settings.width, range: 0.1...1.0, step: 0.05)
            
            Divider()
            
            // MARK: - Audio Dynamics
            SettingsSlider(label: "Dynamics", value: $settings.powerCurve, range: 1.0...3.0, step: 0.1)
            SettingsSlider(label: "Attack", value: $settings.attack, range: 0.5...1.0, step: 0.05)
            SettingsSlider(label: "Release", value: $settings.release, range: 0.1...0.5, step: 0.05)

            // MARK: - Appearance & Color
            colorSettingsSection
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onAppear {
            if let spectrumSettings = layer.effectSettings as? SpectrumSettings {
                settings = spectrumSettings
            }
        }
        .onChange(of: settings) { _, newValue in
            layer.effectSettings = newValue
            VisualizerSceneManager.shared.save()
        }

        Divider()
    }

    // MARK: - Subviews

    @ViewBuilder
    private var colorSettingsSection: some View {
        Divider()
        
        if layer.channelMode == .stereo {
            Toggle("Sync Colors", isOn: $settings.colorSync)
                .padding(.vertical, 4)

            if settings.colorSync {
                ChannelColorSettingsView(colorSettings: $settings.colorSettings)
            } else {
                VStack(spacing: 12) {
                    Group {
                        SectionHeader(title: "Left Channel")
                        ChannelColorSettingsView(colorSettings: $settings.leftColorSettings)
                    }
                    
                    Group {
                        SectionHeader(title: "Right Channel")
                        ChannelColorSettingsView(colorSettings: $settings.rightColorSettings)
                    }
                }
            }
        } else {
            ChannelColorSettingsView(colorSettings: $settings.colorSettings)
        }
    }

    // MARK: - Helper Functions

    private func applyAnchorPosition(_ anchor: SpectrumAnchor) {
        // 將座標邏輯封裝，保持 onChange 簡潔
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
        VisualizerSceneManager.shared.save()
    }
}
