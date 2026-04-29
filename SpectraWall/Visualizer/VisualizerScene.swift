//
//  VisualizerScene.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SpriteKit
import Combine

class VisualizerScene: SKScene {
    private var effectNodes: [UUID: SKNode] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var currentSceneID: UUID?

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        observeSceneChanges()
    }

    private func observeSceneChanges() {
        VisualizerSceneManager.shared.$activeSceneID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadActiveScene()
            }
            .store(in: &cancellables)

        // Monitor active scene's layer changes
        VisualizerSceneManager.shared.$scenes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncActiveSceneLayers()
            }
            .store(in: &cancellables)
    }

    private var perLayerCancellables = Set<AnyCancellable>()

    private func reloadActiveScene() {
        perLayerCancellables.removeAll()
        effectNodes.values.forEach { $0.removeFromParent() }
        effectNodes = [:]

        guard let scene = VisualizerSceneManager.shared.activeScene else { return }
        currentSceneID = scene.id

        for (index, layer) in scene.layers.enumerated() {
            addEffectNode(for: layer, zPosition: CGFloat(index))
        }

        observeLayerProperties(scene.layers)

        scene.$layers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newLayers in
                self?.syncActiveSceneLayers()
                self?.observeLayerProperties(newLayers)
            }
            .store(in: &perLayerCancellables)
    }

    private func observeLayerProperties(_ layers: [LayerSettings]) {
        for layer in layers {
            layer.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self, id = layer.id] _ in
                    self?.effectNodes[id]?.isHidden = !layer.isVisible
                }
                .store(in: &perLayerCancellables)
        }
    }

    private func syncActiveSceneLayers() {
        guard let scene = VisualizerSceneManager.shared.activeScene else {
            effectNodes.values.forEach { $0.removeFromParent() }
            effectNodes = [:]
            currentSceneID = nil
            return
        }

        // If scene changed, reloadActiveScene() will be called by activeSceneID observer
        guard scene.id == currentSceneID else { return }

        let newLayers = scene.layers
        let newIDs = Set(newLayers.map { $0.id })
        let existingIDs = Set(effectNodes.keys)

        for id in existingIDs.subtracting(newIDs) {
            effectNodes[id]?.removeFromParent()
            effectNodes.removeValue(forKey: id)
        }

        for layer in newLayers where !existingIDs.contains(layer.id) {
            let zPosition = CGFloat(newLayers.firstIndex(where: { $0.id == layer.id }) ?? 0)
            addEffectNode(for: layer, zPosition: zPosition)
        }

        for (index, layer) in newLayers.enumerated() {
            effectNodes[layer.id]?.zPosition = CGFloat(index)
            effectNodes[layer.id]?.isHidden = !layer.isVisible
        }
    }

    private func addEffectNode(for layer: LayerSettings, zPosition: CGFloat) {
        let node: SKNode
        switch layer.effectType {
        case .spectrum:
            node = SpectrumEffect(size: size, settings: layer)
        case .orb:
            node = OrbEffect(size: size, settings: layer)
        case .border:
            node = BorderEffect(size: size, settings: layer)
        }
        node.zPosition = zPosition
        node.isHidden = !layer.isVisible
        addChild(node)
        effectNodes[layer.id] = node
    }

    override func update(_ currentTime: TimeInterval) {
        for node in effectNodes.values {
            if node.isHidden { continue }
            if let border = node as? BorderEffect {
                border.update(currentTime)
            }
        }
    }
}
