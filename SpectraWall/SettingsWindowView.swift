//
//  SettingsWindowView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var visualizerSettings = VisualizerSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: - 音訊分析
            SectionHeader(title: "音訊分析")

            VStack(spacing: 10) {
                SettingsSlider(label: "低頻壓制", value: $visualizerSettings.bassAttenuation, range: 0...40, step: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()

            // MARK: - Spectrum
            SectionHeader(title: "Spectrum")

            VStack(spacing: 10) {
                SettingsSlider(label: "高度", value: $visualizerSettings.spectrumGain, range: 0.5...3.0, step: 0.1)
                SettingsSlider(label: "差異化", value: $visualizerSettings.spectrumPowerCurve, range: 1.0...3.0, step: 0.1)
                SettingsSlider(label: "反應速度", value: $visualizerSettings.spectrumAttack, range: 0.5...1.0, step: 0.05)
                SettingsSlider(label: "衰減速度", value: $visualizerSettings.spectrumRelease, range: 0.1...0.5, step: 0.05)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()

            // MARK: - Orb
            SectionHeader(title: "Orb")

            VStack(spacing: 10) {
                SettingsSlider(label: "靈敏度", value: $visualizerSettings.orbBoost, range: 1.0...6.0, step: 0.1)
                SettingsSlider(label: "反應速度", value: $visualizerSettings.orbAttack, range: 0.3...1.0, step: 0.05)
                SettingsSlider(label: "衰減速度", value: $visualizerSettings.orbRelease, range: 0.1...0.5, step: 0.05)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()

            // MARK: - Reset
            HStack {
                Spacer()
                Button("恢復預設值") {
                    visualizerSettings.resetToDefaults()
                }
                .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 16)
        }
        .frame(width: 480)
    }
}
