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
        VStack(alignment: .leading, spacing: 16) {
            modePicker
            
            Divider()
                .padding(.vertical, 4)
            
            colorPickerSection
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .animation(.spring(duration: 0.2), value: colorSettings.colorMode)
    }

    // MARK: - Subviews

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color Mode")
                .font(.headline)
            
            Picker("Color Mode", selection: $colorSettings.colorMode) {
                ForEach(ChannelColorMode.allCases, id: \.self) { mode in
                    Text(mode.localized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var colorPickerSection: some View {
        switch colorSettings.colorMode {
        case .rainbow:
            Text("Auto-generated spectrum colors")
                .font(.caption)
                .foregroundColor(.secondary)
            
        case .gradient:
            VStack(spacing: 12) {
                ColorPickerRow(label: "Start Color", colorData: $colorSettings.gradientColorLow)
                ColorPickerRow(label: "End Color", colorData: $colorSettings.gradientColorHigh)
            }
            
        case .solid:
            ColorPickerRow(label: "Base Color", colorData: $colorSettings.solidColor)
        }
    }
}
