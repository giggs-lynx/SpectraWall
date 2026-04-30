//
//  VisualizerSceneManager.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/28.
//

import SwiftUI
import Combine
import OSLog

class VisualizerSceneManager: ObservableObject {
    static let shared = VisualizerSceneManager()

    @Published var scenes: [SceneSettings] = []
    @Published var activeSceneID: UUID?

    private let scenesKey = "visualizerScenes"
    private let activeSceneKey = "activeSceneID"
    
    private let logger = Logger(subsystem: "com.giggs.SpectraWall", category: "Persistence")
    
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var saveCancellable: AnyCancellable?

    private init() {
        load()
        setupSavePipeline()
        ensureDefaultScene()
    }

    var activeScene: SceneSettings? {
        scenes.first { $0.id == activeSceneID }
    }

    // MARK: - Scene Operations

    func addScene(name: String = "New Scene") -> SceneSettings {
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

        if scenes.isEmpty { return nil }
        let newIndex = min(index, scenes.count - 1)
        return scenes[newIndex]
    }

    func setActiveScene(_ scene: SceneSettings) {
        activeSceneID = scene.id
        save()
    }

    // MARK: - Layer Operations

    @discardableResult
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

    // MARK: - Persistence Logic

    func save() {
        saveSubject.send()
    }
    
    func saveImmediately() {
        performSave()
    }

    private func setupSavePipeline() {
        saveCancellable = saveSubject
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.performSave()
            }
    }

    private func performSave() {
        do {
            let data = try JSONEncoder().encode(scenes)
            UserDefaults.standard.set(data, forKey: scenesKey)
            
            if let activeID = activeSceneID {
                UserDefaults.standard.set(activeID.uuidString, forKey: activeSceneKey)
            }
            
            logger.info("Successfully persisted scenes to UserDefaults")
        } catch {
            logger.error("Failed to encode scenes: \(error.localizedDescription, privacy: .public)")
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: scenesKey),
           let saved = try? JSONDecoder().decode([SceneSettings].self, from: data) {
            self.scenes = saved
        }
        
        if let idString = UserDefaults.standard.string(forKey: activeSceneKey),
           let id = UUID(uuidString: idString) {
            self.activeSceneID = id
        }
    }

    private func ensureDefaultScene() {
        if scenes.isEmpty {
            let defaultScene = SceneSettings(name: "Default Scene")
            defaultScene.layers = [LayerSettings(effectType: .spectrum)]
            scenes = [defaultScene]
            activeSceneID = defaultScene.id
            saveImmediately()
        } else if activeSceneID == nil || activeScene == nil {
            activeSceneID = scenes.first?.id
        }
    }
}
