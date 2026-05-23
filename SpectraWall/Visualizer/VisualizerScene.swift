//
//  VisualizerScene.swift
//  SpectraWall
//

import AppKit
import Combine

class EffectsCoordinator: NSObject {

    private let screen: NSScreen
    private let size: CGSize

    // Metal-based effects
    private var borderEffects: [UUID: BorderEffect] = [:]
    private var spectrumEffects: [UUID: SpectrumEffect] = [:]
    private var orbEffects: [UUID: OrbEffect] = [:]

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
        let newIDs    = Set(newLayers.map { $0.id })
        let existing  = Set(borderEffects.keys)
            .union(Set(spectrumEffects.keys))
            .union(Set(orbEffects.keys))

        // Remove orphaned effects
        for id in existing.subtracting(newIDs) {
            borderEffects[id]?.stop();   borderEffects.removeValue(forKey: id)
            spectrumEffects[id]?.stop(); spectrumEffects.removeValue(forKey: id)
            orbEffects[id]?.stop();      orbEffects.removeValue(forKey: id)
        }

        // Add or update
        for layer in newLayers {
            switch layer.effectType {
            case .border:
                if borderEffects[layer.id] == nil {
                    borderEffects[layer.id] = BorderEffect(size: size, layer: layer, screen: screen)
                }
            case .spectrum:
                if spectrumEffects[layer.id] == nil {
                    spectrumEffects[layer.id] = SpectrumEffect(size: size, layer: layer, screen: screen)
                }
            case .orb:
                if orbEffects[layer.id] == nil {
                    orbEffects[layer.id] = OrbEffect(size: size, layer: layer, screen: screen)
                }
            }
            updateEffectVisuals(for: layer)
        }
    }

    private func updateEffectVisuals(for layer: LayerSettings) {
        if let e = borderEffects[layer.id]  { e.isVisible = layer.isVisible; e.opacity = Float(layer.opacity); return }
        if let e = spectrumEffects[layer.id] { e.isVisible = layer.isVisible; e.opacity = Float(layer.opacity); return }
        if let e = orbEffects[layer.id]     { e.isVisible = layer.isVisible; e.opacity = Float(layer.opacity); return }
    }

    // MARK: - Cleanup

    private func stopAllEffects() {
        borderEffects.values.forEach  { $0.stop() }; borderEffects.removeAll()
        spectrumEffects.values.forEach { $0.stop() }; spectrumEffects.removeAll()
        orbEffects.values.forEach     { $0.stop() }; orbEffects.removeAll()
    }

    deinit { stopAllEffects() }
}
