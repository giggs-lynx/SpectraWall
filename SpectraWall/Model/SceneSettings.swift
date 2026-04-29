//
//  SceneSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/28.
//

import SwiftUI
import Combine

class SceneSettings: ObservableObject, Codable, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var layers: [LayerSettings]

    init(name: String = "Scene") {
        self.id = UUID()
        self.name = name
        self.layers = []
    }

    convenience init(copying source: SceneSettings) {
        self.init(name: source.name + " 副本")
        self.layers = source.layers.map { LayerSettings(copying: $0) }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, layers
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        layers = try c.decode([LayerSettings].self, forKey: .layers)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(layers, forKey: .layers)
    }
}
