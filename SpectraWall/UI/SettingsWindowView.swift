//
//  SettingsWindowView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var layerManager = VisualizerLayerManager.shared
    @State private var selectedLayerID: UUID? = nil

    let globalID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - 左側 Layer 列表
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedLayerID) {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            Text("全局設定")
                        }
                        .padding(.vertical, 2)
                        .tag(globalID)
                    }

                    Section {
                        ForEach(layerManager.layers) { layer in
                            LayerRow(layer: layer)
                                .tag(layer.id)
                        }
                        .onMove { source, destination in
                            layerManager.moveLayer(from: source, to: destination)
                        }
                        .onDelete { offsets in
                            layerManager.removeLayer(at: offsets)
                            if let id = selectedLayerID,
                               !layerManager.layers.contains(where: { $0.id == id }) {
                                selectedLayerID = nil
                            }
                        }
                    } header: {
                        HStack {
                            Text("Layers")
                            Spacer()
                            Menu {
                                Button("Spectrum") {
                                    layerManager.addLayer(effectType: .spectrum)
                                }
                                Button("Orb") {
                                    layerManager.addLayer(effectType: .orb)
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .menuIndicator(.hidden)
                            .menuStyle(.borderlessButton)
                            .frame(width: 20)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 200)

            Divider()

            // MARK: - 右側參數設定
            if selectedLayerID == globalID {
                GlobalSettingsView()
            } else if let id = selectedLayerID,
                      let layer = layerManager.layers.first(where: { $0.id == id }) {
                LayerSettingsView(layer: layer)
            } else {
                VStack {
                    Spacer()
                    Text("選擇一個 Layer 來編輯")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 580, height: 480)
    }
}

// MARK: - Layer Row

struct LayerRow: View {
    @ObservedObject var layer: LayerSettings

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: layer.effectType == .spectrum ? "waveform.path" : "circle.circle")
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(layer.effectType.rawValue)
            Spacer()
            Button {
                layer.isVisible.toggle()
                VisualizerLayerManager.shared.save()
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundColor(layer.isVisible ? .primary : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Layer Settings View

struct LayerSettingsView: View {
    @ObservedObject var layer: LayerSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch layer.effectType {
                case .spectrum:
                    SpectrumSettingsSection(layer: layer)
                case .orb:
                    OrbSettingsSection(layer: layer)
                }

                Divider()

                HStack {
                    Button("刪除此 Layer") {
                        if let id = layer.id as UUID?,
                           let index = VisualizerLayerManager.shared.layers.firstIndex(where: { $0.id == id }) {
                            VisualizerLayerManager.shared.removeLayer(at: IndexSet([index]))
                        }
                    }
                    .foregroundColor(.red)
                    .padding(.leading, 20)
                    Spacer()
                    Button("恢復預設值") {
                        layer.resetToDefaults()
                        VisualizerLayerManager.shared.save()
                    }
                    .foregroundColor(.secondary)
                    .padding(.trailing, 20)
                }
                .padding(.vertical, 16)
            }
        }
    }
}

// MARK: - Spectrum Settings

struct SpectrumSettingsSection: View {
    @ObservedObject var layer: LayerSettings

    var body: some View {
        SectionHeader(title: "Spectrum")
        VStack(spacing: 10) {
            Picker("聲道", selection: $layer.channelMode) {
                ForEach(ChannelMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            SettingsSlider(label: "高度", value: $layer.spectrumGain, range: 0.5...3.0, step: 0.1)
            SettingsSlider(label: "差異化", value: $layer.spectrumPowerCurve, range: 1.0...3.0, step: 0.1)
            SettingsSlider(label: "反應速度", value: $layer.spectrumAttack, range: 0.5...1.0, step: 0.05)
            SettingsSlider(label: "衰減速度", value: $layer.spectrumRelease, range: 0.1...0.5, step: 0.05)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)

        Divider()
    }
}

// MARK: - Orb Settings

struct OrbSettingsSection: View {
    @ObservedObject var layer: LayerSettings

    var body: some View {
        SectionHeader(title: "Orb")
        VStack(spacing: 10) {
            Picker("聲道", selection: $layer.channelMode) {
                ForEach(ChannelMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            SettingsSlider(label: "靈敏度", value: $layer.orbBoost, range: 1.0...6.0, step: 0.1)
            SettingsSlider(label: "反應速度", value: $layer.orbAttack, range: 0.3...1.0, step: 0.05)
            SettingsSlider(label: "衰減速度", value: $layer.orbRelease, range: 0.1...0.5, step: 0.05)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)

        Divider()
    }
}

// MARK: - Global Settings View

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
