//
//  VisualizerSceneManager.swift
//  SpectraWall
//
//  Owns the in-memory scene library and active-scene cursor. Persistence:
//    - each scene → `scenes/scene-<uuid>.json`
//    - registry (which UUIDs exist + order + active) → `config.json`
//
//  Save timing:
//    - structural changes (add / dup / remove / move scene or layer) save
//      synchronously so the on-disk layout matches in-memory state immediately
//    - property changes (slider drags etc.) call save() which debounces a
//      single write 1s after the last edit
//

import SwiftUI
import Combine
import OSLog

class VisualizerSceneManager: ObservableObject {
    static let shared = VisualizerSceneManager()

    @Published var scenes: [SceneSettings] = []
    @Published var activeSceneID: UUID?

    /// UUIDs that are listed in config.json's `scenes` but whose individual
    /// scene-<uuid>.json files failed to decode. Skipped from the in-memory
    /// `scenes` array (so the UI doesn't render them) but preserved in the
    /// on-disk registry: the file stays put so the user can hand-fix it
    /// instead of losing it to the next orphan sweep.
    private var unreadableSceneIDs: [UUID] = []

    private let logger = Logger(subsystem: AppConstants.bundleId, category: "Persistence")
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var saveCancellable: AnyCancellable?

    private init() {
        load()
        setupSavePipeline()
        ensureDefaultScene()
    }

    var activeScene: SceneSettings? {
        guard let id = activeSceneID else { return scenes.first }
        return scenes.first { $0.id == id } ?? scenes.first
    }

    // MARK: - Scene Operations

    @discardableResult
    func addScene(name: String = "New Scene") -> SceneSettings {
        let scene = SceneSettings(name: name)
        scenes.append(scene)
        persistImmediately()
        return scene
    }

    @discardableResult
    func duplicateScene(_ scene: SceneSettings) -> SceneSettings {
        let copy = SceneSettings(copying: scene)
        if let index = scenes.firstIndex(where: { $0 === scene }) {
            scenes.insert(copy, at: index + 1)
        } else {
            scenes.append(copy)
        }
        persistImmediately()
        return copy
    }

    func removeScene(_ scene: SceneSettings) -> SceneSettings? {
        guard let index = scenes.firstIndex(where: { $0 === scene }) else { return nil }
        let removed = scenes.remove(at: index)
        XDGStorage.shared.deleteScene(uuid: removed.id)
        if activeSceneID == removed.id {
            activeSceneID = scenes.first?.id
        }
        persistImmediately()

        if scenes.isEmpty { return nil }
        let newIndex = min(index, scenes.count - 1)
        return scenes[newIndex]
    }

    func setActiveScene(_ scene: SceneSettings) {
        guard scenes.contains(where: { $0 === scene }) else { return }
        activeSceneID = scene.id
        persistImmediately()
    }

    // MARK: - Layer Operations

    @discardableResult
    func addLayer(to scene: SceneSettings, effectType: EffectType) -> LayerSettings {
        let layer = LayerSettings(effectType: effectType)
        scene.layers.append(layer)
        persistImmediately()
        return layer
    }

    func duplicateLayer(_ layer: LayerSettings, in scene: SceneSettings) -> LayerSettings {
        let copy = LayerSettings(copying: layer)
        if let index = scene.layers.firstIndex(where: { $0 === layer }) {
            scene.layers.insert(copy, at: index + 1)
        } else {
            scene.layers.append(copy)
        }
        persistImmediately()
        return copy
    }

    func removeLayer(_ layer: LayerSettings, from scene: SceneSettings) -> LayerSettings? {
        guard let index = scene.layers.firstIndex(where: { $0 === layer }) else { return nil }
        scene.layers.remove(at: index)
        persistImmediately()

        if scene.layers.isEmpty { return nil }
        let newIndex = min(index, scene.layers.count - 1)
        return scene.layers[newIndex]
    }

    func moveLayer(in scene: SceneSettings, from source: IndexSet, to destination: Int) {
        scene.layers.move(fromOffsets: source, toOffset: destination)
        scene.objectWillChange.send()
        persistImmediately()
    }

    // MARK: - Persistence

    /// Debounced save — used by property changes (slider drags, color picker).
    /// Coalesces a burst into one write 1s after the last edit.
    func save() {
        saveSubject.send()
    }

    /// Synchronous save — used on app terminate.
    func saveImmediately() {
        performSave()
    }

    private func setupSavePipeline() {
        saveCancellable = saveSubject
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.performSave() }
    }

    /// Used by structural changes that should land on disk now, not 1s later.
    private func persistImmediately() {
        performSave()
    }

    private func performSave() {
        // 1. Write every live scene's file. XDGStorage refuses writes while
        //    configFileIsBroken; the early-return mirrors that contract.
        if XDGStorage.shared.configFileIsBroken { return }
        for scene in scenes {
            XDGStorage.shared.saveScene(scene)
        }
        // 2. Drop orphaned scene-<uuid>.json files. Keep both live IDs AND
        //    unreadable IDs so a hand-edit typo on one scene doesn't lose it
        //    the next time the user adds/removes another scene.
        let keep = Set(scenes.map(\.id)).union(unreadableSceneIDs)
        XDGStorage.shared.deleteScenesNotIn(keep)
        // 3. Update config.json registry (scenes order + active). Unreadable
        //    IDs are appended so they survive the round-trip.
        var config = XDGStorage.shared.loadConfig() ?? AppConfig()
        config.scenes = scenes.map(\.id) + unreadableSceneIDs
        config.activeScene = activeSceneID ?? scenes.first?.id
        XDGStorage.shared.saveConfig(config)
    }

    private func load() {
        guard let config = XDGStorage.shared.loadConfig() else { return }
        var loaded: [SceneSettings] = []
        var unreadable: [UUID] = []
        for uuid in config.scenes {
            if let scene = XDGStorage.shared.loadScene(uuid: uuid) {
                loaded.append(scene)
            } else if FileManager.default.fileExists(
                atPath: XDGStorage.shared.sceneFileURL(for: uuid).path
            ) {
                // File on disk but undecodable — preserve it for the user to
                // hand-repair instead of treating it as an orphan.
                unreadable.append(uuid)
                logger.error("""
                    Skipping unreadable scene \(uuid.uuidString, privacy: .public). \
                    File preserved on disk; fix or remove manually.
                    """)
            }
        }
        scenes = loaded
        unreadableSceneIDs = unreadable
        if let active = config.activeScene, scenes.contains(where: { $0.id == active }) {
            activeSceneID = active
        } else {
            activeSceneID = scenes.first?.id
        }
    }

    private func ensureDefaultScene() {
        // If config.json is broken we deliberately don't write a default scene
        // — that would trample the user's likely-recoverable file.
        if XDGStorage.shared.configFileIsBroken { return }
        if scenes.isEmpty && unreadableSceneIDs.isEmpty {
            let defaultScene = SceneSettings(name: "Default Scene")
            defaultScene.layers = [LayerSettings(effectType: .spectrum)]
            scenes = [defaultScene]
            activeSceneID = defaultScene.id
            performSave()
        } else if activeSceneID == nil ||
                  !scenes.contains(where: { $0.id == activeSceneID }) {
            activeSceneID = scenes.first?.id
        }
    }
}
