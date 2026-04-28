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

        // 監聽 active scene 的 layers 變化
        VisualizerSceneManager.shared.$scenes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncActiveSceneLayers()
            }
            .store(in: &cancellables)
    }

    private func reloadActiveScene() {
        effectNodes.values.forEach { $0.removeFromParent() }
        effectNodes = [:]

        guard let scene = VisualizerSceneManager.shared.activeScene else { return }
        currentSceneID = scene.id

        for (index, layer) in scene.layers.enumerated() {
            addEffectNode(for: layer, zPosition: CGFloat(index))
        }

        // 監聽這個 scene 的 layers 變化
        scene.$layers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncActiveSceneLayers()
            }
            .store(in: &cancellables)
    }

    private func syncActiveSceneLayers() {
        guard let scene = VisualizerSceneManager.shared.activeScene,
              scene.id == currentSceneID else {
            reloadActiveScene()
            return
        }

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
