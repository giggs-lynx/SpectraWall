//
//  VisualizerScene.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SpriteKit
import Combine

/// Protocol to handle frame-based updates for effect nodes
protocol UpdatableEffectNode {
    func update(_ currentTime: TimeInterval)
}

class VisualizerScene: SKScene {
    private var effectNodes: [UUID: SKNode] = [:]
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
        // Observe active scene switching
        VisualizerSceneManager.shared.$activeSceneID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadActiveScene() }
            .store(in: &cancellables)

        // Observe general scenes array for structural changes
        VisualizerSceneManager.shared.$scenes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncActiveSceneLayers() }
            .store(in: &cancellables)
    }

    private func observeLayerProperties(_ layers: [LayerSettings]) {
        // Clear previous layer-specific observers to avoid memory leaks
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
        perLayerCancellables.removeAll()
        sceneStructureCancellables.removeAll()

        guard let scene = VisualizerSceneManager.shared.activeScene else {
            currentSceneID = nil
            return
        }
        
        currentSceneID = scene.id
        syncActiveSceneLayers()

        // Observe internal layer list changes (Add/Remove/Move)
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
        let newIDs = Set(newLayers.map { $0.id })
        let existingIDs = Set(effectNodes.keys)

        // 1. Remove orphaned nodes
        for id in existingIDs.subtracting(newIDs) {
            effectNodes[id]?.removeFromParent()
            effectNodes.removeValue(forKey: id)
        }

        // 2. Add or Update nodes
        for (index, layer) in newLayers.enumerated() {
            let node: SKNode
            if let existingNode = effectNodes[layer.id] {
                node = existingNode
            } else {
                node = createNode(for: layer)
                addChild(node)
                effectNodes[layer.id] = node
            }
            
            // Sync dynamic properties
            node.zPosition = CGFloat(index)
            updateNodeVisuals(for: layer)
        }
    }

    private func updateNodeVisuals(for layer: LayerSettings) {
        guard let node = effectNodes[layer.id] else { return }
        node.isHidden = !layer.isVisible
        node.alpha = CGFloat(layer.opacity)
    }

    // MARK: - Node Factory

    private func addEffectNode(for layer: LayerSettings, zPosition: CGFloat) {
        let node = createNode(for: layer)
        node.zPosition = zPosition
        updateNodeVisuals(for: layer)
        addChild(node)
        effectNodes[layer.id] = node
    }

    private func createNode(for layer: LayerSettings) -> SKNode {
        switch layer.effectType {
        case .spectrum: return SpectrumEffect(size: size, settings: layer)
        case .orb:      return OrbEffect(size: size, settings: layer)
        case .border:   return BorderEffect(size: size, settings: layer)
        }
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        for node in effectNodes.values {
            guard !node.isHidden else { continue }
            
            // Use protocol instead of specific class casting for better performance
            if let updatable = node as? UpdatableEffectNode {
                updatable.update(currentTime)
            }
        }
    }
}
