//
//  PresetStore.swift
//  SpectraWall
//
//  User-saved scene presets: named snapshots of a scene's layer stack that
//  can be re-instantiated as new scenes or exported/imported as JSON files.
//  Wire format IS SceneSettings' Codable ({version, name, layers}), so a
//  preset file is byte-compatible with scenes/scene-<uuid>.json. Presets
//  live in presets/preset-<uuid>.json with no config.json registry — the
//  directory is the library.
//

import Combine
import Foundation
import OSLog

enum PresetImportError: LocalizedError {
    case malformed
    case unsupportedVersion(found: Int)
    case unknownEffectType(rawValue: String)

    var errorDescription: String? {
        switch self {
        case .malformed:
            return String(localized: "The file could not be read as a SpectraWall preset.")
        case .unsupportedVersion(let found):
            return String(localized: "This preset was created by a newer version of SpectraWall (format \(found)).")
        case .unknownEffectType(let rawValue):
            return String(localized: "This preset uses an unknown effect type “\(rawValue)”.")
        }
    }
}

class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published private(set) var presets: [SceneSettings] = []

    private let storage: XDGStorage

    init(storage: XDGStorage = .shared) {
        self.storage = storage
        presets = storage.listPresetUUIDs()
            .compactMap { storage.loadPreset(uuid: $0) }
        sortPresets()
    }

    // MARK: - Library operations

    /// Snapshots a scene into the preset library. Deep-copies via an
    /// encode→decode round trip rather than SceneSettings(copying:) — the
    /// copying init appends " Copy" to the name, while the round trip keeps
    /// the wire format authoritative and mints fresh layer UUIDs for free.
    @discardableResult
    func savePreset(from scene: SceneSettings, name: String) -> SceneSettings? {
        guard let snapshot = roundTripCopy(of: scene) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        snapshot.name = trimmed.isEmpty ? scene.name : trimmed
        storage.savePreset(snapshot)
        presets.append(snapshot)
        sortPresets()
        return snapshot
    }

    func deletePreset(_ preset: SceneSettings) {
        storage.deletePreset(uuid: preset.id)
        presets.removeAll { $0 === preset }
    }

    /// Creates a new scene from a preset, adds it to the scene library, and
    /// makes it active. The preset itself is untouched.
    @discardableResult
    func instantiate(_ preset: SceneSettings) -> SceneSettings? {
        guard let copy = roundTripCopy(of: preset) else { return nil }
        return VisualizerSceneManager.shared.addScene(from: copy)
    }

    // MARK: - Export / Import

    func exportData(for scene: SceneSettings) throws -> Data {
        try XDGStorage.encodeJSONForDisk(scene)
    }

    /// Decodes and validates an imported preset/scene file. Validation must
    /// happen after decode: EffectType is a RawRepresentable<String> struct
    /// so ANY string decodes successfully, and LayerSettings silently falls
    /// back to Spectrum defaults for types the registry doesn't know —
    /// accepting that would produce a zombie layer that loses its settings
    /// on the next save, so reject instead.
    static func decodeImport(_ data: Data) throws -> SceneSettings {
        guard let scene = try? JSONDecoder().decode(SceneSettings.self, from: data) else {
            throw PresetImportError.malformed
        }
        guard scene.version <= 1 else {
            throw PresetImportError.unsupportedVersion(found: scene.version)
        }
        if let unknown = scene.layers.first(where: { EffectRegistry.descriptor(for: $0.effectType) == nil }) {
            throw PresetImportError.unknownEffectType(rawValue: unknown.effectType.rawValue)
        }
        return scene
    }

    /// Imports a preset file as a new scene (added to the library and made
    /// active — same behavior as instantiating a stored preset).
    @discardableResult
    func importScene(from url: URL) throws -> SceneSettings {
        guard let data = try? Data(contentsOf: url) else {
            throw PresetImportError.malformed
        }
        let scene = try Self.decodeImport(data)
        if scene.name.trimmingCharacters(in: .whitespaces).isEmpty {
            scene.name = url.deletingPathExtension().lastPathComponent
        }
        return VisualizerSceneManager.shared.addScene(from: scene)
    }

    // MARK: - Helpers

    private func roundTripCopy(of scene: SceneSettings) -> SceneSettings? {
        guard let data = try? XDGStorage.encodeJSONForDisk(scene),
              let copy = try? JSONDecoder().decode(SceneSettings.self, from: data)
        else {
            AppLog.persist.error("Preset round-trip copy failed for \"\(scene.name, privacy: .public)\"")
            return nil
        }
        return copy
    }

    private func sortPresets() {
        presets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
