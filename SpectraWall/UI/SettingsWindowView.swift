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
    @State private var selectedSceneID: UUID?
    @State private var selectedLayerID: UUID?
    
    private let globalID = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
    
    var selectedScene: SceneSettings? {
        sceneManager.scenes.first { $0.id == selectedSceneID }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Column: Scene List
            SceneListColumn(
                globalID: globalID,
                selectedSceneID: $selectedSceneID,
                selectedLayerID: $selectedLayerID
            )
            .frame(width: 260)
            
            Divider()
            
            // MARK: - Middle Column: Effect List
            middleColumn
            
            Divider()
            
            // MARK: - Right Column: Settings Content
            rightColumn
        }
        .frame(width: 1200, height: 560)
        .onAppear {
            selectedSceneID = globalID
        }
    }
    
    // MARK: - Subviews

    @ViewBuilder
    private var middleColumn: some View {
        if selectedSceneID == globalID {
            Spacer()
        } else if let scene = selectedScene {
            EffectListColumn(
                scene: scene,
                selectedLayerID: $selectedLayerID
            )
            .frame(width: 260)
        } else {
            placeholderView(text: "No Scene Selected")
                .frame(width: 260)
        }
    }

    @ViewBuilder
    private var rightColumn: some View {
        if selectedSceneID == globalID {
            GlobalSettingsView()
        } else if let id = selectedLayerID,
                  let layer = selectedScene?.layers.first(where: { $0.id == id }) {
            LayerSettingsView(layer: layer)
        } else if selectedScene != nil {
            placeholderView(text: "Click + to add an effect")
                .frame(maxWidth: .infinity)
        } else {
            placeholderView(text: "No Scene Selected")
                .frame(maxWidth: .infinity)
        }
    }

    private func placeholderView(text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
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
    @State private var sceneToDelete: SceneSettings?
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSceneID) {
                // Global Settings Row
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text("General")
                }
                .padding(.vertical, 2)
                .tag(globalID)
                
                Divider()
                
                Section {
                    ForEach(sceneManager.scenes) { scene in
                        SceneRow(
                            scene: scene,
                            isActive: sceneManager.activeScene === scene,
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
                    headerView
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedSceneID) {
                selectedLayerID = nil
                if let scene = sceneManager.scenes.first(where: { $0.id == selectedSceneID }) {
                    selectedLayerID = scene.layers.first?.id
                }
            }
        }
        .confirmationDialog(
            "Are you sure you want to delete \"\(sceneToDelete?.name ?? "")\"?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Delete", role: .destructive) {
                if let scene = sceneToDelete {
                    let next = sceneManager.removeScene(scene)
                    selectedSceneID = next?.id ?? globalID
                    selectedLayerID = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var headerView: some View {
        HStack {
            Text("Scenes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
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

// MARK: - Scene Row (Keeping logic as requested)
struct SceneRow: View {
    @ObservedObject var scene: SceneSettings
    let isActive: Bool
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var isEditing = false
    @State private var editingName = ""
    
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
            
            if isEditing {
                TextField("", text: $editingName)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(scene.name)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") { startEditing() }
            Button("Duplicate") { onDuplicate() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
    
    private func startEditing() {
        editingName = scene.name
        isEditing = true
    }
    
    private func commitRename() {
        if !editingName.trimmingCharacters(in: .whitespaces).isEmpty {
            scene.name = editingName
            VisualizerSceneManager.shared.save()
        }
        isEditing = false
    }
}

// MARK: - Effect List Column (Keeping logic as requested)
struct EffectListColumn: View {
    @ObservedObject var scene: SceneSettings
    @Binding var selectedLayerID: UUID?
    @State private var showDeleteConfirm = false
    @State private var layerToDelete: LayerSettings?

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
                        addEffectMenu
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .confirmationDialog(
            "Are you sure you want to delete \"\(layerToDelete?.name ?? "")\"?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Delete", role: .destructive) {
                if let layer = layerToDelete {
                    let next = VisualizerSceneManager.shared.removeLayer(layer, from: scene)
                    selectedLayerID = next?.id
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var addEffectMenu: some View {
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

// MARK: - Effect Row (Keeping logic as requested)
struct EffectRow: View {
    @ObservedObject var layer: LayerSettings
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var isEditing = false
    @State private var editingName = ""
    
    var body: some View {
        HStack(spacing: 8) {
            effectIcon
            
            if isEditing {
                TextField("", text: $editingName)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(layer.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            visibilityButton
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") { startEditing() }
            Button("Duplicate") { onDuplicate() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var effectIcon: some View {
        let name: String = {
            switch layer.effectType {
            case .spectrum: return "spectrum"
            case .orb:      return "orb"
            case .border:   return "border"
            default:        return "spectrum"
            }
        }()
        return Image(name)
            .renderingMode(.template)
            .resizable()
            .frame(width: 16, height: 16)
            .foregroundColor(.secondary)
    }

    private var visibilityButton: some View {
        Button {
            layer.isVisible.toggle()
            VisualizerSceneManager.shared.save()
        } label: {
            Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                .foregroundColor(layer.isVisible ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    private func startEditing() {
        editingName = layer.name
        isEditing = true
    }
    
    private func commitRename() {
        if !editingName.trimmingCharacters(in: .whitespaces).isEmpty {
            layer.name = editingName
            VisualizerSceneManager.shared.save()
        }
        isEditing = false
    }
}
