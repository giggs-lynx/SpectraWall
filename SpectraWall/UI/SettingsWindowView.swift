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
        .frame(width: 640, height: 560)
    }
}

// MARK: - Layer Row

struct LayerRow: View {
    @ObservedObject var layer: LayerSettings
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: layer.effectType == .spectrum ? "waveform.path" : "circle.circle")
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(layer.name)
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
        .contextMenu {
            Button("複製") {
                VisualizerLayerManager.shared.duplicateLayer(layer)
            }
            Divider()
            Button("刪除", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .confirmationDialog("確定要刪除「\(layer.name)」嗎？", isPresented: $showDeleteConfirm) {
            Button("刪除", role: .destructive) {
                if let index = VisualizerLayerManager.shared.layers.firstIndex(where: { $0.id == layer.id }) {
                    VisualizerLayerManager.shared.removeLayer(at: IndexSet([index]))
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - Layer Settings View

struct LayerSettingsView: View {
    @ObservedObject var layer: LayerSettings
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // 名稱
                SectionHeader(title: "名稱")
                TextField("Layer 名稱", text: $layer.name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .onChange(of: layer.name) {
                        VisualizerLayerManager.shared.save()
                    }

                Divider()

                CommonSettingsSection(layer: layer)

                Divider()

                switch layer.effectType {
                case .spectrum:
                    SpectrumSettingsSection(layer: layer)
                case .orb:
                    OrbSettingsSection(layer: layer)
                }

                Divider()

                HStack {
                    Button("刪除此 Layer") {
                        showDeleteConfirm = true
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
        .confirmationDialog("確定要刪除「\(layer.name)」嗎？", isPresented: $showDeleteConfirm) {
            Button("刪除", role: .destructive) {
                if let index = VisualizerLayerManager.shared.layers.firstIndex(where: { $0.id == layer.id }) {
                    VisualizerLayerManager.shared.removeLayer(at: IndexSet([index]))
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - Common Settings

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

// MARK: - Spectrum Settings

struct SpectrumSettingsSection: View {
    @ObservedObject var layer: LayerSettings

    var body: some View {
        SectionHeader(title: "Spectrum")
        VStack(spacing: 10) {
            Picker("貼邊方向", selection: $layer.spectrumAnchor) {
                ForEach(SpectrumAnchor.allCases, id: \.self) { anchor in
                    Text(anchor.rawValue).tag(anchor)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: layer.spectrumAnchor) {
                switch layer.spectrumAnchor {
                case .bottom:
                    layer.positionY = 0.0
                    layer.positionX = 0.5
                case .top:
                    layer.positionY = 1.0
                    layer.positionX = 0.5
                case .left:
                    layer.positionX = 0.0
                    layer.positionY = 0.5
                case .right:
                    layer.positionX = 1.0
                    layer.positionY = 0.5
                }
                VisualizerLayerManager.shared.save()
            }
            SettingsSlider(label: "高度", value: $layer.spectrumGain, range: 0.5...3.0, step: 0.1)
            SettingsSlider(label: "高度上限", value: $layer.spectrumMaxHeight, range: 0.1...1.0, step: 0.05)
            SettingsSlider(label: "寬度", value: $layer.spectrumWidth, range: 0.1...1.0, step: 0.05)
            SettingsSlider(label: "差異化", value: $layer.spectrumPowerCurve, range: 1.0...3.0, step: 0.1)
            SettingsSlider(label: "反應速度", value: $layer.spectrumAttack, range: 0.5...1.0, step: 0.05)
            SettingsSlider(label: "衰減速度", value: $layer.spectrumRelease, range: 0.1...0.5, step: 0.05)

            Divider()

            // 顏色模式
            Picker("顏色模式", selection: $layer.spectrumColorMode) {
                ForEach(SpectrumColorMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if layer.spectrumColorMode == .solid {
                ColorPickerRow(label: "顏色", colorData: $layer.spectrumSolidColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - Orb Settings

struct OrbSettingsSection: View {
    @ObservedObject var layer: LayerSettings

    var body: some View {
        SectionHeader(title: "Orb")
        VStack(spacing: 10) {
            SettingsSlider(label: "靈敏度", value: $layer.orbBoost, range: 1.0...6.0, step: 0.1)
            SettingsSlider(label: "反應速度", value: $layer.orbAttack, range: 0.3...1.0, step: 0.05)
            SettingsSlider(label: "衰減速度", value: $layer.orbRelease, range: 0.1...0.5, step: 0.05)
            SettingsSlider(label: "基礎半徑", value: $layer.orbBaseRadius, range: 40...300, step: 5)
            SettingsSlider(label: "外圈倍數", value: $layer.orbOuterRadiusMultiplier, range: 1.0...3.0, step: 0.1)

            Divider()

            SectionHeader(title: "內圈顏色")
            ColorPickerRow(label: "低頻色", colorData: $layer.orbInnerColorLow)
            ColorPickerRow(label: "高頻色", colorData: $layer.orbInnerColorHigh)

            Divider()

            SectionHeader(title: "外圈顏色")
            ColorPickerRow(label: "低頻色", colorData: $layer.orbOuterColorLow)
            ColorPickerRow(label: "高頻色", colorData: $layer.orbOuterColorHigh)
            SettingsSlider(label: "外圈透明度", value: $layer.orbOuterOpacity, range: 0.0...1.0, step: 0.05)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
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

// MARK: - Color Picker Row

struct ColorPickerRow: View {
    let label: String
    @Binding var colorData: ColorData

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { colorData.color },
                set: { newColor in
                    if let nsColor = NSColor(newColor).usingColorSpace(.deviceRGB) {
                        colorData = ColorData(nsColor)
                    }
                }
            ))
            .labelsHidden()
        }
    }
}
