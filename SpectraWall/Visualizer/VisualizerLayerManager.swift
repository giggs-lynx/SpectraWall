//
//  VisualizerLayerManager.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

// SpectraWall/Visualizer/VisualizerLayerManager.swift
import SwiftUI
import Combine

class VisualizerLayerManager: ObservableObject {
    static let shared = VisualizerLayerManager()

    @Published var layers: [LayerSettings] = []

    private let saveKey = "visualizerLayers"

    init() {
        load()
        if layers.isEmpty {
            // 預設加一個 Spectrum layer
            layers = [LayerSettings(effectType: .spectrum)]
        }
    }

    func addLayer(effectType: EffectType) {
        layers.append(LayerSettings(effectType: effectType))
        save()
    }

    func removeLayer(at offsets: IndexSet) {
        layers.remove(atOffsets: offsets)
        save()
    }

    func moveLayer(from source: IndexSet, to destination: Int) {
        layers.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(layers) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode([LayerSettings].self, from: data) else { return }
        layers = saved
    }
}
