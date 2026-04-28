//
//  ChannelColorSettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/28.
//

import SwiftUI

struct ChannelColorSettingsView: View {
    @Binding var colorSettings: ChannelColorSettings

    var body: some View {
        Picker("顏色模式", selection: $colorSettings.colorMode) {
            ForEach(ChannelColorMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        switch colorSettings.colorMode {
        case .rainbow:
            EmptyView()
        case .gradient:
            ColorPickerRow(label: "起始色", colorData: $colorSettings.gradientColorLow)
            ColorPickerRow(label: "結束色", colorData: $colorSettings.gradientColorHigh)
        case .solid:
            ColorPickerRow(label: "顏色", colorData: $colorSettings.solidColor)
        }
    }
}
