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
        Picker("Color Mode", selection: $colorSettings.colorMode) {
            ForEach(ChannelColorMode.allCases, id: \.self) { mode in
                Text(mode.localized).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        switch colorSettings.colorMode {
        case .rainbow:
            EmptyView()
        case .gradient:
            ColorPickerRow(label: "Start Color", colorData: $colorSettings.gradientColorLow)
            ColorPickerRow(label: "End Color", colorData: $colorSettings.gradientColorHigh)
        case .solid:
            ColorPickerRow(label: "Color", colorData: $colorSettings.solidColor)
        }
    }
}
