//
//  BorderSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

struct BorderSettingsSection: View {
    @ObservedObject var layer: LayerSettings

    private var borderBinding: Binding<BorderSettings> {
        Binding(
            get: { layer.effectSettings as? BorderSettings ?? .defaults },
            set: { layer.effectSettings = $0 }
        )
    }

    var body: some View {
        SectionHeader(title: "Border")
        VStack(spacing: 10) {
            Picker("條數", selection: borderBinding.strokeCount) {
                Text("1 條").tag(1)
                Text("2 條").tag(2)
            }
            .pickerStyle(.segmented)

            Toggle("順時針", isOn: borderBinding.clockwise)

            SettingsSlider(label: "速度", value: borderBinding.speed, range: 0.05...0.5, step: 0.05)
            SettingsSlider(label: "尾巴長度", value: borderBinding.tailLength, range: 0.05...0.8, step: 0.05)
            SettingsSlider(label: "線條寬度", value: borderBinding.baseWidth, range: 1.0...20.0, step: 0.5)
            SettingsSlider(label: "圓角", value: borderBinding.cornerRadius, range: 0...100, step: 5)
            SettingsSlider(label: "Pulse 反應速度", value: borderBinding.pulseAttack, range: 0.3...1.0, step: 0.05)
            SettingsSlider(label: "Pulse 衰減速度", value: borderBinding.pulseRelease, range: 0.05...0.5, step: 0.05)

            Divider()

            SectionHeader(title: "第 1 條顏色")
            ColorPickerRow(label: "頭部", colorData: borderBinding.stroke1ColorStart)
            ColorPickerRow(label: "尾部", colorData: borderBinding.stroke1ColorEnd)

            if borderBinding.strokeCount.wrappedValue == 2 {
                Divider()
                SectionHeader(title: "第 2 條顏色")
                ColorPickerRow(label: "頭部", colorData: borderBinding.stroke2ColorStart)
                ColorPickerRow(label: "尾部", colorData: borderBinding.stroke2ColorEnd)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)

        Divider()
    }
}
