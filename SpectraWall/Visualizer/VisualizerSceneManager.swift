//
//  VisualizerSceneManager.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/28.
//

import SwiftUI
import Combine

class VisualizerSceneManager: ObservableObject {
    static let shared = VisualizerSceneManager()

    @Published var scenes: [SceneSettings] = []
    @Published var activeSceneID: UUID?

    private let scenesKey = "visualizerScenes"
    private let activeSceneKey = "activeSceneID"

    init() {
        load()
        if scenes.isEmpty {
            let defaultScene = SceneSettings(name: "Scene 1")
            defaultScene.layers = [LayerSettings(effectType: .spectrum)]
            scenes = [defaultScene]
            activeSceneID = defaultScene.id
            save()
        }
        if activeSceneID == nil {
            activeSceneID = scenes.first?.id
        }
    }

    var activeScene: SceneSettings? {
        scenes.first { $0.id == activeSceneID }
    }

    // MARK: - Scene Operations

    func addScene(name: String = "Scene") -> SceneSettings {
        let scene = SceneSettings(name: name)
        scenes.append(scene)
        save()
        return scene
    }

    func duplicateScene(_ scene: SceneSettings) -> SceneSettings {
        let copy = SceneSettings(copying: scene)
        if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
            scenes.insert(copy, at: index + 1)
        } else {
            scenes.append(copy)
        }
        save()
        return copy
    }

    func removeScene(_ scene: SceneSettings) -> SceneSettings? {
        guard let index = scenes.firstIndex(where: { $0.id == scene.id }) else { return nil }
        scenes.remove(at: index)

        if activeSceneID == scene.id {
            activeSceneID = scenes.first?.id
        }

        save()

        // Return the scene to auto-select
        if scenes.isEmpty { return nil }
        let newIndex = min(index, scenes.count - 1)
        return scenes[newIndex]
    }

    func setActiveScene(_ scene: SceneSettings) {
        activeSceneID = scene.id
        save()
    }

    // MARK: - Layer Operations

    func addLayer(to scene: SceneSettings, effectType: EffectType) -> LayerSettings {
        let layer = LayerSettings(effectType: effectType)
        scene.layers.append(layer)
        save()
        return layer
    }

    func duplicateLayer(_ layer: LayerSettings, in scene: SceneSettings) -> LayerSettings {
        let copy = LayerSettings(copying: layer)
        if let index = scene.layers.firstIndex(where: { $0.id == layer.id }) {
            scene.layers.insert(copy, at: index + 1)
        } else {
            scene.layers.append(copy)
        }
        save()
        return copy
    }

    func removeLayer(_ layer: LayerSettings, from scene: SceneSettings) -> LayerSettings? {
        guard let index = scene.layers.firstIndex(where: { $0.id == layer.id }) else { return nil }
        scene.layers.remove(at: index)
        save()

        if scene.layers.isEmpty { return nil }
        let newIndex = min(index, scene.layers.count - 1)
        return scene.layers[newIndex]
    }

    func moveLayer(in scene: SceneSettings, from source: IndexSet, to destination: Int) {
        scene.layers.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(scenes) {
            UserDefaults.standard.set(data, forKey: scenesKey)
        }
        if let activeID = activeSceneID {
            UserDefaults.standard.set(activeID.uuidString, forKey: activeSceneKey)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: scenesKey),
           let saved = try? JSONDecoder().decode([SceneSettings].self, from: data) {
            scenes = saved
        }
        if let idString = UserDefaults.standard.string(forKey: activeSceneKey),
           let id = UUID(uuidString: idString) {
            activeSceneID = id
        }
    }
}
