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

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        setupLayers()
        observeLayerChanges()
    }

    private func setupLayers() {
        // 清掉舊的
        effectNodes.values.forEach { $0.removeFromParent() }
        effectNodes = [:]

        let manager = VisualizerLayerManager.shared
        for (index, layer) in manager.layers.enumerated() {
            addEffectNode(for: layer, zPosition: CGFloat(index))
        }
    }

    private func addEffectNode(for layer: LayerSettings, zPosition: CGFloat) {
        let node: SKNode
        switch layer.effectType {
        case .spectrum:
            node = SpectrumEffect(size: size, settings: layer)
        case .orb:
            node = OrbEffect(size: size, settings: layer)
        }
        node.zPosition = zPosition
        node.isHidden = !layer.isVisible
        addChild(node)
        effectNodes[layer.id] = node
    }

    private func observeLayerChanges() {
        VisualizerLayerManager.shared.$layers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupLayers()
            }
            .store(in: &cancellables)
    }
}
