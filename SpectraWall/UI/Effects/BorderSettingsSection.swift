//
//  BorderSettingsSection.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI
import Combine

struct BorderSettingsSection: View {
    @ObservedObject var layer: LayerSettings
    @State private var settings: BorderSettings = .defaults

    var body: some View {
        SectionHeader(title: "Border")
        
        VStack(spacing: 10) {
            // MARK: - Animation Control
            HStack {
                Picker("Stroke Count", selection: $settings.strokeCount) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                .pickerStyle(.segmented)
                
                Toggle("Clockwise", isOn: $settings.clockwise)
                    .toggleStyle(.button)
            }

            // MARK: - Geometric Settings
            SettingsSlider(label: "Speed", value: $settings.speed, range: 0.05...0.5, step: 0.05)
            SettingsSlider(label: "Tail Length", value: $settings.tailLength, range: 0.05...0.8, step: 0.05)
            SettingsSlider(label: "Line Width", value: $settings.baseWidth, range: 1.0...20.0, step: 0.5)
            SettingsSlider(label: "Corner Radius", value: $settings.cornerRadius, range: 0...100, step: 5)
            
            Divider()
            
            // MARK: - Audio Response
            SettingsSlider(label: "Pulse Attack", value: $settings.pulseAttack, range: 0.3...1.0, step: 0.05)
            SettingsSlider(label: "Pulse Release", value: $settings.pulseRelease, range: 0.05...0.5, step: 0.05)

            // MARK: - Appearance
            strokeColorSettings
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onAppear {
            if let borderSettings = layer.effectSettings as? BorderSettings {
                settings = borderSettings
            }
        }
        .onChange(of: layer.id) { _, _ in
            if let borderSettings = layer.effectSettings as? BorderSettings {
                settings = borderSettings
            }
        }
        .onChange(of: settings) { _, newValue in
            if let current = layer.effectSettings as? BorderSettings, current == newValue {
                return
            }
            layer.effectSettings = newValue
            VisualizerSceneManager.shared.save()
        }
        .onReceive(layer.objectWillChange) { _ in
            if let borderSettings = layer.effectSettings as? BorderSettings,
               borderSettings != settings {
                settings = borderSettings
            }
        }

        Divider()
    }

    @ViewBuilder
    private var strokeColorSettings: some View {
        Divider()
        SectionHeader(title: "First Stroke")
        ColorPickerRow(label: "Head", colorData: $settings.stroke1ColorStart)
        ColorPickerRow(label: "Tail", colorData: $settings.stroke1ColorEnd)

        if settings.strokeCount == 2 {
            Divider()
            SectionHeader(title: "Second Stroke")
            ColorPickerRow(label: "Head", colorData: $settings.stroke2ColorStart)
            ColorPickerRow(label: "Tail", colorData: $settings.stroke2ColorEnd)
        }
    }
}
