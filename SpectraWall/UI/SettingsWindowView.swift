//
//  SettingsWindowView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI
import ServiceManagement

struct SettingsWindowView: View {
    @ObservedObject var sceneManager = VisualizerSceneManager.shared
    @State private var selectedSceneID: UUID? = nil
    @State private var selectedLayerID: UUID? = nil

    let globalID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    var selectedScene: SceneSettings? {
        sceneManager.scenes.first { $0.id == selectedSceneID }
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - 左欄：Scene 列表
            SceneListColumn(
                globalID: globalID,
                selectedSceneID: $selectedSceneID,
                selectedLayerID: $selectedLayerID
            )
            .frame(width: 160)

            Divider()

            // MARK: - 中欄：Effect 列表
            if selectedSceneID == globalID {
                Spacer()
            } else if let scene = selectedScene {
                EffectListColumn(
                    scene: scene,
                    selectedLayerID: $selectedLayerID
                )
                .frame(width: 160)
            } else {
                VStack {
                    Spacer()
                    Text("選擇一個場景")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .frame(width: 160)
            }

            Divider()

            // MARK: - 右欄：設定內容
            if selectedSceneID == globalID {
                GlobalSettingsView()
            } else if let id = selectedLayerID,
                      let layer = selectedScene?.layers.first(where: { $0.id == id }) {
                LayerSettingsView(layer: layer)
            } else if selectedScene != nil {
                VStack {
                    Spacer()
                    Text("按 + 新增一個 Effect")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("選擇一個場景來編輯")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 800, height: 560)
        .onAppear {
            // 預設選中全局設定
            selectedSceneID = globalID
        }
    }
}

// MARK: - Scene List Column

struct SceneListColumn: View {
    let globalID: UUID
    @Binding var selectedSceneID: UUID?
    @Binding var selectedLayerID: UUID?
    @ObservedObject var sceneManager = VisualizerSceneManager.shared
    @State private var showDeleteConfirm = false
    @State private var sceneToDelete: SceneSettings? = nil

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSceneID) {
                // 全局設定
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text("全局設定")
                }
                .padding(.vertical, 2)
                .tag(globalID)

                Divider()

                Section {
                    ForEach(sceneManager.scenes) { scene in
                        SceneRow(
                            scene: scene,
                            isActive: sceneManager.activeSceneID == scene.id,
                            onDuplicate: {
                                let copy = sceneManager.duplicateScene(scene)
                                selectedSceneID = copy.id
                                selectedLayerID = nil
                            },
                            onDelete: {
                                sceneToDelete = scene
                                showDeleteConfirm = true
                            }
                        )
                        .tag(scene.id)
                    }
                } header: {
                    HStack {
                        Text("場景")
                        Spacer()
                        Button {
                            let scene = sceneManager.addScene()
                            selectedSceneID = scene.id
                            selectedLayerID = nil
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedSceneID) {
                selectedLayerID = nil
            }
        }
        .confirmationDialog(
            "確定要刪除「\(sceneToDelete?.name ?? "")」嗎？",
            isPresented: $showDeleteConfirm
        ) {
            Button("刪除", role: .destructive) {
                if let scene = sceneToDelete {
                    let next = sceneManager.removeScene(scene)
                    selectedSceneID = next?.id ?? globalID
                    selectedLayerID = nil
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - Scene Row

struct SceneRow: View {
    @ObservedObject var scene: SceneSettings
    let isActive: Bool
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                VisualizerSceneManager.shared.setActiveScene(scene)
            } label: {
                Image(systemName: isActive ? "circle.fill" : "circle")
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            Text(scene.name)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("複製") { onDuplicate() }
            Divider()
            Button("刪除", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Effect List Column

struct EffectListColumn: View {
    @ObservedObject var scene: SceneSettings
    @Binding var selectedLayerID: UUID?
    @State private var showDeleteConfirm = false
    @State private var layerToDelete: LayerSettings? = nil

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedLayerID) {
                Section {
                    ForEach(scene.layers) { layer in
                        EffectRow(
                            layer: layer,
                            onDuplicate: {
                                let copy = VisualizerSceneManager.shared.duplicateLayer(layer, in: scene)
                                selectedLayerID = copy.id
                            },
                            onDelete: {
                                layerToDelete = layer
                                showDeleteConfirm = true
                            }
                        )
                        .tag(layer.id)
                    }
                    .onMove { source, destination in
                        VisualizerSceneManager.shared.moveLayer(in: scene, from: source, to: destination)
                    }
                } header: {
                    HStack {
                        Text("Effects")
                        Spacer()
                        Menu {
                            Button("Spectrum") {
                                let layer = VisualizerSceneManager.shared.addLayer(to: scene, effectType: .spectrum)
                                selectedLayerID = layer.id
                            }
                            Button("Orb") {
                                let layer = VisualizerSceneManager.shared.addLayer(to: scene, effectType: .orb)
                                selectedLayerID = layer.id
                            }
                            Button("Border") {
                                let layer = VisualizerSceneManager.shared.addLayer(to: scene, effectType: .border)
                                selectedLayerID = layer.id
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
        .confirmationDialog(
            "確定要刪除「\(layerToDelete?.name ?? "")」嗎？",
            isPresented: $showDeleteConfirm
        ) {
            Button("刪除", role: .destructive) {
                if let layer = layerToDelete {
                    let next = VisualizerSceneManager.shared.removeLayer(layer, from: scene)
                    selectedLayerID = next?.id
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - Effect Row

struct EffectRow: View {
    @ObservedObject var layer: LayerSettings
    let onDuplicate: () -> Void
    let onDelete: () -> Void

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
                .lineLimit(1)
            Spacer()
            Button {
                layer.isVisible.toggle()
                VisualizerSceneManager.shared.save()
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundColor(layer.isVisible ? .primary : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("複製") { onDuplicate() }
            Divider()
            Button("刪除", role: .destructive) { onDelete() }
        }
    }
}
