//
//  CommonSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

struct CommonSettingsSection: View {
    @ObservedObject var layer: LayerSettings

    var body: some View {
        SectionHeader(title: "共用設定")
        VStack(spacing: 10) {
            Picker("聲道", selection: $layer.channelMode) {
                ForEach(ChannelMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            SettingsSlider(label: "透明度", value: $layer.opacity, range: 0.0...1.0, step: 0.05)
            SettingsSlider(label: "位置 X", value: $layer.positionX, range: 0.0...1.0, step: 0.01)
            SettingsSlider(label: "位置 Y", value: $layer.positionY, range: 0.0...1.0, step: 0.01)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}
