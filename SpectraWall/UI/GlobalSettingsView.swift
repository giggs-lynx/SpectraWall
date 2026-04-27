//
//  GlobalSettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

struct GlobalSettingsView: View {
    @ObservedObject var visualizerSettings = VisualizerSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "音訊分析")
                VStack(spacing: 10) {
                    SettingsSlider(
                        label: "低頻壓制",
                        value: $visualizerSettings.bassAttenuation,
                        range: 0...40,
                        step: 1
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                Divider()

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
        }
    }
}
