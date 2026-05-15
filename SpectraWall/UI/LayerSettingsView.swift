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
                SectionHeader(title: "Name")
                TextField("Layer Name", text: $layer.name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .onChange(of: layer.name) {
                        VisualizerSceneManager.shared.save()
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
                    Button("Delete Layer") {
                        showDeleteConfirm = true
                    }
                    .foregroundColor(.red)
                    .padding(.leading, 20)
                    Spacer()
                    Button("Reset to Defaults") {
                        layer.resetToDefaults()
                        VisualizerSceneManager.shared.save()
                    }
                    .foregroundColor(.secondary)
                    .padding(.trailing, 20)
                }
                .padding(.vertical, 16)
            }
        }
        .confirmationDialog("Are you sure you want to delete \"\(layer.name)\"?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let scene = VisualizerSceneManager.shared.scenes.first(where: {
                    $0.layers.contains(where: { $0.id == layer.id })
                }) {
                    _ = VisualizerSceneManager.shared.removeLayer(layer, from: scene)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
