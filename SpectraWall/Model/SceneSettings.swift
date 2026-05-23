//
//  SceneSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/28.
//

import SwiftUI
import Combine

class SceneSettings: ObservableObject, Codable, Identifiable {
    /// UUID that doubles as both the SwiftUI Identifiable ID and the on-disk
    /// filename derivation (`scene-<uuid>.json`). Not encoded in the scene's
    /// JSON content — the filename carries it. Settable so the manager can
    /// stamp the right UUID after reading from disk.
    var id: UUID
    @Published var name: String
    @Published var layers: [LayerSettings]

    /// Scene-file schema version. Hand-written into JSON for future migration
    /// dispatch. Decoder tolerates absence (legacy + sandbox JSON has no
    /// version field) and falls back to 1.
    var version: Int

    /// id is intentionally absent — filename carries the UUID.
    enum CodingKeys: String, CodingKey {
        case version, name, layers
    }

    init(name: String = "Scene") {
        self.id = UUID()
        self.name = name
        self.layers = []
        self.version = 1
    }

    convenience init(copying source: SceneSettings) {
        self.init(name: source.name + " Copy")
        self.layers = source.layers.map { LayerSettings(copying: $0) }
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Manager overwrites id after decode (from filename); start with a
        // throwaway value so the property is initialised.
        self.id = UUID()
        self.version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        self.name = try container.decode(String.self, forKey: .name)
        self.layers = try container.decode([LayerSettings].self, forKey: .layers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(name, forKey: .name)
        try container.encode(layers, forKey: .layers)
    }
}
