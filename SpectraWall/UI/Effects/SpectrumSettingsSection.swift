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
            Picker("貼邊方向", selection: $settings.anchor) {
                ForEach(SpectrumAnchor.allCases, id: \.self) { anchor in
                    Text(anchor.rawValue).tag(anchor)
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

            SettingsSlider(label: "高度", value: $settings.gain, range: 0.5...3.0, step: 0.1)
            SettingsSlider(label: "高度上限", value: $settings.maxHeight, range: 0.1...1.0, step: 0.05)
            SettingsSlider(label: "寬度", value: $settings.width, range: 0.1...1.0, step: 0.05)
            SettingsSlider(label: "差異化", value: $settings.powerCurve, range: 1.0...3.0, step: 0.1)
            SettingsSlider(label: "反應速度", value: $settings.attack, range: 0.5...1.0, step: 0.05)
            SettingsSlider(label: "衰減速度", value: $settings.release, range: 0.1...0.5, step: 0.05)

            Divider()

            if layer.channelMode == .stereo {
                Toggle("左右聲道同步顏色", isOn: $settings.colorSync)

                if settings.colorSync {
                    ChannelColorSettingsView(colorSettings: $settings.colorSettings)
                } else {
                    SectionHeader(title: "左聲道")
                    ChannelColorSettingsView(colorSettings: $settings.leftColorSettings)
                    SectionHeader(title: "右聲道")
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
