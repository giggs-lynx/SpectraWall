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
    
    override func update(_ currentTime: TimeInterval) {
        for node in effectNodes.values {
            if node.isHidden { continue }
            if let border = node as? BorderEffect {
                border.update(currentTime)
            }
        }
    }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        setupLayers()
        observeLayerChanges()
    }

    private func setupLayers() {
        effectNodes.values.forEach { $0.removeFromParent() }
        effectNodes = [:]

        for (index, layer) in VisualizerLayerManager.shared.layers.enumerated() {
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
        case .border:
            node = BorderEffect(size: size, settings: layer)
        }
        node.zPosition = zPosition
        node.isHidden = !layer.isVisible
        addChild(node)
        effectNodes[layer.id] = node
    }

    private func observeLayerChanges() {
        VisualizerLayerManager.shared.$layers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] layers in
                self?.setupLayers()
                // 同時監聽每個 layer 的屬性變化
                self?.observeEachLayer(layers)
            }
            .store(in: &cancellables)
    }

    private func observeEachLayer(_ layers: [LayerSettings]) {
        for layer in layers {
            layer.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncLayerVisibility()
                }
                .store(in: &cancellables)
        }
    }

    private func syncLayerVisibility() {
        for layer in VisualizerLayerManager.shared.layers {
            effectNodes[layer.id]?.isHidden = !layer.isVisible
        }
    }
}
