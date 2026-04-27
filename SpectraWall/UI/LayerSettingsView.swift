//
//  LayerSettingsView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

struct LayerSettingsView: View {
    @ObservedObject var layer: LayerSettings
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
                case .border:
                    BorderSettingsSection(layer: layer)
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
