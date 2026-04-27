//
//  SettingsWindowView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

// SpectraWall/UI/SettingsWindowView.swift
import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var layerManager = VisualizerLayerManager.shared
    @State private var selectedLayerID: UUID? = nil

    let globalID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var body: some View {
        HStack(spacing: 0) {
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
                                Button("Spectrum") { layerManager.addLayer(effectType: .spectrum) }
                                Button("Orb") { layerManager.addLayer(effectType: .orb) }
                                Button("Border") { layerManager.addLayer(effectType: .border) }
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
            Image(systemName: {
                switch layer.effectType {
                case .spectrum: return "waveform.path"
                case .orb: return "circle.circle"
                case .border: return "rectangle.on.rectangle"
                }
            }())
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

// MARK: - Channel Color Settings View

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
