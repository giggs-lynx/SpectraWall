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
    // Tracks which effect-type sections have been instantiated. We never remove
    // entries; once a section is built it stays alive so switching back to that
    // type is a cheap frame change instead of a full ColorPicker rebuild.
    @State private var instantiatedTypes: Set<EffectType> = []

    var body: some View {
        ScrollView {
            // Spacing 0: each SettingsCard carries its own bottom margin, so the
            // height-0 collapse of inactive effect sections leaves no phantom gap.
            VStack(alignment: .leading, spacing: 0) {
                SettingsCard(title: "Name") {
                    TextField("Layer Name", text: $layer.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: layer.name) {
                            VisualizerSceneManager.shared.save()
                        }
                }

                CommonSettingsSection(layer: layer)

                // Build sections lazily but never remove them: the first time
                // the user picks a layer of a given effect type, that section
                // pays its one-time creation cost (~400ms for ColorPickers).
                // Subsequent switches between already-instantiated types are
                // just frame collapses, no rebuild.
                ForEach(EffectRegistry.allTypes, id: \.self) { type in
                    if instantiatedTypes.contains(type),
                       let descriptor = EffectRegistry.descriptor(for: type) {
                        descriptor.makeSettingsView(layer)
                            .frame(height: layer.effectType == type ? nil : 0)
                            .clipped()
                            .allowsHitTesting(layer.effectType == type)
                    }
                }

                HStack {
                    Button("Delete Layer") {
                        showDeleteConfirm = true
                    }
                    .foregroundColor(.red)
                    Spacer()
                    Button("Reset to Defaults") {
                        layer.resetToDefaults()
                        VisualizerSceneManager.shared.save()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.top, Spacing.sm)
            }
            .padding(Spacing.xl)
        }
        .onAppear { instantiatedTypes.insert(layer.effectType) }
        .onChange(of: layer.effectType) { _, newType in
            instantiatedTypes.insert(newType)
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
