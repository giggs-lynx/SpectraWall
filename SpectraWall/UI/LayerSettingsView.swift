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
                        VisualizerSceneManager.shared.save()
                    }

                Divider()

                CommonSettingsSection(layer: layer)
                    .id(layer.id)

                Divider()

                switch layer.effectType {
                case .spectrum:
                    SpectrumSettingsSection(layer: layer)
                        .id(layer.id)
                case .orb:
                    OrbSettingsSection(layer: layer)
                        .id(layer.id)
                case .border:
                    BorderSettingsSection(layer: layer)
                        .id(layer.id)
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
                        VisualizerSceneManager.shared.save()
                    }
                    .foregroundColor(.secondary)
                    .padding(.trailing, 20)
                }
                .padding(.vertical, 16)
            }
        }
        .id(layer.id)
        .confirmationDialog("確定要刪除「\(layer.name)」嗎？", isPresented: $showDeleteConfirm) {
            Button("刪除", role: .destructive) {
                if let scene = VisualizerSceneManager.shared.scenes.first(where: {
                    $0.layers.contains(where: { $0.id == layer.id })
                }) {
                    _ = VisualizerSceneManager.shared.removeLayer(layer, from: scene)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}
