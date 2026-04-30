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

    enum CodingKeys: String, CodingKey {
        case id, name, layers
    }

    init(name: String = "Scene") {
        self.id = UUID()
        self.name = name
        self.layers = []
    }

    convenience init(copying source: SceneSettings) {
        self.init(name: source.name + " Copy")
        self.layers = source.layers.map { LayerSettings(copying: $0) }
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.layers = try container.decode([LayerSettings].self, forKey: .layers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(layers, forKey: .layers)
    }
}
