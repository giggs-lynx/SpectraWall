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
            SettingsSlider(label: "靈敏度", value: $settings.boost, range: 1.0...6.0, step: 0.1)
            SettingsSlider(label: "反應速度", value: $settings.attack, range: 0.3...1.0, step: 0.05)
            SettingsSlider(label: "衰減速度", value: $settings.release, range: 0.1...0.5, step: 0.05)
            SettingsSlider(label: "基礎半徑", value: $settings.baseRadius, range: 40...300, step: 5)
            SettingsSlider(label: "外圈倍數", value: $settings.outerRadiusMultiplier, range: 1.0...3.0, step: 0.1)

            Divider()

            SectionHeader(title: "內圈顏色")
            ColorPickerRow(label: "低頻色", colorData: $settings.innerColorLow)
            ColorPickerRow(label: "高頻色", colorData: $settings.innerColorHigh)

            Divider()

            SectionHeader(title: "外圈顏色")
            ColorPickerRow(label: "低頻色", colorData: $settings.outerColorLow)
            ColorPickerRow(label: "高頻色", colorData: $settings.outerColorHigh)
            SettingsSlider(label: "外圈透明度", value: $settings.outerOpacity, range: 0.0...1.0, step: 0.05)
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
