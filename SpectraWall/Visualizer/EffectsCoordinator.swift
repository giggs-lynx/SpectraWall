//
//  VisualizerScene.swift
//  SpectraWall
//
//  EffectsCoordinator owns the live `[UUID: any Effect]` set for one screen.
//  Effect construction goes through EffectRegistry; the coordinator itself
//  doesn't know which concrete classes exist.
//

import AppKit
import Combine
import OSLog

class EffectsCoordinator: NSObject {

    private let screen: NSScreen
    private let size: CGSize

    /// Live effects on this screen, keyed by their layer UUID.
    private var effects: [UUID: any Effect] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var perLayerCancellables = Set<AnyCancellable>()
    private var sceneStructureCancellables = Set<AnyCancellable>()
    private var currentSceneID: UUID?

    init(size: CGSize, screen: NSScreen) {
        self.size   = size
        self.screen = screen
        super.init()
        observeSceneChanges()
    }

    // MARK: - Observation

    private func observeSceneChanges() {
        VisualizerSceneManager.shared.$activeSceneID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadActiveScene() }
            .store(in: &cancellables)

        VisualizerSceneManager.shared.$scenes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncActiveSceneLayers() }
            .store(in: &cancellables)
    }

    private func observeLayerProperties(_ layers: [LayerSettings]) {
        perLayerCancellables.removeAll()
        for layer in layers {
            layer.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak layer] _ in
                    guard let self, let layer else { return }
                    self.updateEffectVisuals(for: layer)
                }
                .store(in: &perLayerCancellables)
        }
    }

    // MARK: - Scene Management

    private func reloadActiveScene() {
        stopAllEffects()
        perLayerCancellables.removeAll()
        sceneStructureCancellables.removeAll()

        guard let scene = VisualizerSceneManager.shared.activeScene else {
            currentSceneID = nil
            return
        }

        AppLog.scene.info(
            "Active scene switched: \(scene.name, privacy: .public) (id=\(scene.id, privacy: .public))"
        )

        currentSceneID = scene.id
        syncActiveSceneLayers()

        scene.$layers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newLayers in
                self?.syncActiveSceneLayers()
                self?.observeLayerProperties(newLayers)
            }
            .store(in: &sceneStructureCancellables)
    }

    private func syncActiveSceneLayers() {
        guard let scene = VisualizerSceneManager.shared.activeScene,
              scene.id == currentSceneID else { return }

        let newLayers = scene.layers
        let newIDs    = Set(newLayers.map(\.id))

        // Remove orphaned effects in a single pass over the unified dict.
        for id in Set(effects.keys).subtracting(newIDs) {
            effects[id]?.stop()
            effects.removeValue(forKey: id)
        }

        // Create any layer that doesn't have a live effect yet. The registry
        // owns the type → factory mapping; an unknown effectType logs and
        // skips so a forward-compat scene file (referencing a future kind we
        // don't yet ship) doesn't crash the app.
        for layer in newLayers where effects[layer.id] == nil {
            guard let descriptor = EffectRegistry.descriptor(for: layer.effectType) else {
                AppLog.scene.error(
                    "No descriptor for effect type \(layer.effectType.rawValue, privacy: .public); skipping layer"
                )
                continue
            }
            guard let effect = descriptor.makeEffect(size, layer, screen) else {
                AppLog.scene.error(
                    "Factory returned nil for effect type \(layer.effectType.rawValue, privacy: .public)"
                )
                continue
            }
            effects[layer.id] = effect
        }

        // Apply visibility / opacity from the layer onto each live effect.
        for layer in newLayers {
            updateEffectVisuals(for: layer)
        }
    }

    private func updateEffectVisuals(for layer: LayerSettings) {
        guard let effect = effects[layer.id] else { return }
        effect.isVisible = layer.isVisible
        effect.opacity = Float(layer.opacity)
    }

    // MARK: - Cleanup

    private func stopAllEffects() {
        effects.values.forEach { $0.stop() }
        effects.removeAll()
    }

    deinit { stopAllEffects() }
}
