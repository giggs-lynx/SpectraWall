//
//  VisualizerScene.swift
//  SpectraWall
//

import SpriteKit
import Combine

/// Protocol to handle frame-based updates for effect nodes
protocol UpdatableEffectNode {
    func update(_ currentTime: TimeInterval)
}

class VisualizerScene: SKScene {
    var screen: NSScreen = NSScreen.screens[0]

    // SpriteKit-based effects (none remaining after Phase 3d)
    private var effectNodes: [UUID: SKNode] = [:]
    // Metal-based effects — managed independently of the SpriteKit render loop
    private var borderEffects: [UUID: BorderEffect] = [:]
    private var spectrumEffects: [UUID: SpectrumEffect] = [:]
    private var orbEffects: [UUID: OrbEffect] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var perLayerCancellables = Set<AnyCancellable>()
    private var sceneStructureCancellables = Set<AnyCancellable>()
    private var currentSceneID: UUID?

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
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
                    guard let self = self, let layer = layer else { return }
                    self.updateNodeVisuals(for: layer)
                }
                .store(in: &perLayerCancellables)
        }
    }

    // MARK: - Scene Management

    private func reloadActiveScene() {
        effectNodes.values.forEach { $0.removeFromParent() }
        effectNodes.removeAll()
        borderEffects.values.forEach { $0.stop() }
        borderEffects.removeAll()
        spectrumEffects.values.forEach { $0.stop() }
        spectrumEffects.removeAll()
        orbEffects.values.forEach { $0.stop() }
        orbEffects.removeAll()
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
        let newIDs      = Set(newLayers.map { $0.id })
        let existingIDs = Set(effectNodes.keys)
            .union(Set(borderEffects.keys))
            .union(Set(spectrumEffects.keys))
            .union(Set(orbEffects.keys))

        // Remove orphaned effects
        for id in existingIDs.subtracting(newIDs) {
            effectNodes[id]?.removeFromParent()
            effectNodes.removeValue(forKey: id)
            borderEffects[id]?.stop()
            borderEffects.removeValue(forKey: id)
            spectrumEffects[id]?.stop()
            spectrumEffects.removeValue(forKey: id)
            orbEffects[id]?.stop()
            orbEffects.removeValue(forKey: id)
        }

        // Add or update
        for (index, layer) in newLayers.enumerated() {
            if layer.effectType == .border {
                if borderEffects[layer.id] == nil {
                    let effect = BorderEffect(size: size, settings: layer, screen: screen)
                    borderEffects[layer.id] = effect
                }
                updateNodeVisuals(for: layer)
            } else if layer.effectType == .spectrum {
                if spectrumEffects[layer.id] == nil {
                    let effect = SpectrumEffect(size: size, settings: layer, screen: screen)
                    spectrumEffects[layer.id] = effect
                }
                updateNodeVisuals(for: layer)
            } else if layer.effectType == .orb {
                if orbEffects[layer.id] == nil {
                    let effect = OrbEffect(size: size, settings: layer, screen: screen)
                    orbEffects[layer.id] = effect
                }
                updateNodeVisuals(for: layer)
            } else {
                let node: SKNode
                if let existing = effectNodes[layer.id] {
                    node = existing
                } else {
                    node = createNode(for: layer)
                    addChild(node)
                    effectNodes[layer.id] = node
                }
                node.zPosition = CGFloat(index)
                updateNodeVisuals(for: layer)
            }
        }
    }

    private func updateNodeVisuals(for layer: LayerSettings) {
        if let border = borderEffects[layer.id] {
            border.isVisible = layer.isVisible
            border.opacity   = Float(layer.opacity)
            return
        }
        if let spectrum = spectrumEffects[layer.id] {
            spectrum.isVisible = layer.isVisible
            spectrum.opacity   = Float(layer.opacity)
            return
        }
        if let orb = orbEffects[layer.id] {
            orb.isVisible = layer.isVisible
            orb.opacity   = Float(layer.opacity)
            return
        }
        guard let node = effectNodes[layer.id] else { return }
        node.isHidden = !layer.isVisible
        node.alpha    = CGFloat(layer.opacity)
    }

    // MARK: - Node Factory (SpriteKit effects only)

    private func createNode(for layer: LayerSettings) -> SKNode {
        switch layer.effectType {
        case .spectrum: fatalError("Spectrum effects are managed separately")
        case .orb:      fatalError("Orb effects are managed separately")
        case .border:   fatalError("Border effects are managed separately")
        }
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        for node in effectNodes.values {
            guard !node.isHidden else { continue }
            if let updatable = node as? UpdatableEffectNode {
                updatable.update(currentTime)
            }
        }
        // Border and Spectrum effects are driven by EffectsRenderer.draw(in:) via tickClients — no call needed here.
    }
}
