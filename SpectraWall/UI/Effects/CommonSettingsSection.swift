//
//  CommonSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

struct CommonSettingsSection: View {
    @ObservedObject var layer: LayerSettings
    @State private var channelMode: ChannelMode = .stereo
    @State private var opacity: Double = 1.0
    @State private var positionX: Double = 0.5
    @State private var positionY: Double = 0.0

    var body: some View {
        SectionHeader(title: "General")
        VStack(spacing: 10) {
            Picker("Channel", selection: $channelMode) {
                ForEach(ChannelMode.allCases, id: \.self) { mode in
                    Text(mode.localized).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            SettingsSlider(label: "Opacity", value: $opacity, range: 0.0...1.0, step: 0.05)
            SettingsSlider(label: "Position X", value: $positionX, range: 0.0...1.0, step: 0.01)
            SettingsSlider(label: "Position Y", value: $positionY, range: 0.0...1.0, step: 0.01)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onAppear {
            channelMode = layer.channelMode
            opacity = layer.opacity
            positionX = layer.positionX
            positionY = layer.positionY
        }
        .onChange(of: channelMode) { _, v in layer.channelMode = v }
        .onChange(of: opacity)     { _, v in layer.opacity = v }
        .onChange(of: positionX)   { _, v in layer.positionX = v }
        .onChange(of: positionY)   { _, v in layer.positionY = v }
    }
}
