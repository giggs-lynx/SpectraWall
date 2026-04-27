//
//  SpectrumSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//
    
import SwiftUI

struct SpectrumSettingsSection: View {
    @ObservedObject var layer: LayerSettings

    private var spectrumBinding: Binding<SpectrumSettings> {
        Binding(
            get: { layer.effectSettings as? SpectrumSettings ?? .defaults },
            set: { layer.effectSettings = $0 }
        )
    }

    var body: some View {
        SectionHeader(title: "Spectrum")
        VStack(spacing: 10) {
            Picker("貼邊方向", selection: spectrumBinding.anchor) {
                ForEach(SpectrumAnchor.allCases, id: \.self) { anchor in
                    Text(anchor.rawValue).tag(anchor)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: spectrumBinding.anchor.wrappedValue) {
                Task { @MainActor in
                    switch spectrumBinding.anchor.wrappedValue {
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
                    VisualizerLayerManager.shared.save()
                }
            }

            SettingsSlider(label: "高度", value: spectrumBinding.gain, range: 0.5...3.0, step: 0.1)
            SettingsSlider(label: "高度上限", value: spectrumBinding.maxHeight, range: 0.1...1.0, step: 0.05)
            SettingsSlider(label: "寬度", value: spectrumBinding.width, range: 0.1...1.0, step: 0.05)
            SettingsSlider(label: "差異化", value: spectrumBinding.powerCurve, range: 1.0...3.0, step: 0.1)
            SettingsSlider(label: "反應速度", value: spectrumBinding.attack, range: 0.5...1.0, step: 0.05)
            SettingsSlider(label: "衰減速度", value: spectrumBinding.release, range: 0.1...0.5, step: 0.05)

            Divider()

            if layer.channelMode == .stereo {
                Toggle("左右聲道同步顏色", isOn: spectrumBinding.colorSync)

                if spectrumBinding.colorSync.wrappedValue {
                    ChannelColorSettingsView(colorSettings: spectrumBinding.colorSettings)
                } else {
                    SectionHeader(title: "左聲道")
                    ChannelColorSettingsView(colorSettings: spectrumBinding.leftColorSettings)
                    SectionHeader(title: "右聲道")
                    ChannelColorSettingsView(colorSettings: spectrumBinding.rightColorSettings)
                }
            } else {
                ChannelColorSettingsView(colorSettings: spectrumBinding.colorSettings)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)

        Divider()
    }
}
