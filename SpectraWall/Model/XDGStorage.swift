//
//  XDGStorage.swift
//  SpectraWall
//
//  Resolves XDG Base Directory paths and provides atomic JSON read/write.
//  Each scene lives in its own file keyed by UUID; `config.json` lists the
//  UUIDs in order and remembers the active scene; `state.json` keeps the
//  per-machine init sentinel.
//
//  Migration paths (one-time, leave originals on disk for rollback):
//    1. legacy sandbox-container UserDefaults plist
//    2. early dev build with everything inline in config.json
//    3. transitional single scenes.json
//    4. transitional per-scene-name files (`scenes/Default Scene.json`)
//
//  Layout:
//    $XDG_CONFIG_HOME / .config       → spectrawall/config.json
//                                        spectrawall/scenes/scene-<uuid>.json
//    $XDG_STATE_HOME  / .local/state  → spectrawall/state.json
//

import CoreGraphics
import Foundation
import OSLog

final class XDGStorage {
    static let shared = XDGStorage()

    let configFileURL: URL
    let scenesDirURL: URL
    let presetsDirURL: URL
    let stateFileURL: URL

    /// Latched true when config.json exists on disk but fails to decode.
    /// While set, all writes (config, scenes, orphan-cleanup) are refused so
    /// a hand-edit typo can't snowball into wiping the scene library on the
    /// next save. Cleared on relaunch after the user fixes/removes the file.
    private(set) var configFileIsBroken: Bool = false

    private let appSlug = "spectrawall"

    private init() {
        let configDir = Self.xdgHome("XDG_CONFIG_HOME", defaultRelative: ".config")
            .appendingPathComponent(appSlug)
        let stateDir = Self.xdgHome("XDG_STATE_HOME", defaultRelative: ".local/state")
            .appendingPathComponent(appSlug)
        configFileURL = configDir.appendingPathComponent("config.json")
        scenesDirURL = configDir.appendingPathComponent("scenes")
        presetsDirURL = configDir.appendingPathComponent("presets")
        stateFileURL = stateDir.appendingPathComponent("state.json")

        runMigrationsIfNeeded()
    }

    /// XDG spec: if env var is unset, empty, or contains a non-absolute path,
    /// fall back to the default relative-to-home directory.
    private static func xdgHome(_ envName: String, defaultRelative: String) -> URL {
        if let value = ProcessInfo.processInfo.environment[envName],
           !value.isEmpty,
           value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(defaultRelative)
    }

    // MARK: - Config / State

    func loadConfig() -> AppConfig? {
        // Distinguish "file missing" (legitimate first-run) from "file present
        // but unreadable" (likely user-edited typo) so writes can be blocked
        // only in the latter case.
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            configFileIsBroken = false
            return nil
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            configFileIsBroken = false
            return config
        } catch {
            AppLog.persist.error("""
                config.json decode failed — refusing further writes to protect \
                user data. \(error.localizedDescription, privacy: .public)
                """)
            configFileIsBroken = true
            return nil
        }
    }

    func saveConfig(_ config: AppConfig) {
        guard !configFileIsBroken else {
            AppLog.persist.error("Refusing to save config.json — on-disk file failed to decode.")
            return
        }
        save(config, to: configFileURL)
    }

    func loadState() -> AppState? { load(AppState.self, from: stateFileURL) }
    func saveState(_ state: AppState) { save(state, to: stateFileURL) }

    // MARK: - Per-scene files (UUID-keyed)

    func sceneFileURL(for uuid: UUID) -> URL {
        scenesDirURL.appendingPathComponent("scene-\(uuid.uuidString).json")
    }

    func loadScene(uuid: UUID) -> SceneSettings? {
        guard let scene = load(SceneSettings.self, from: sceneFileURL(for: uuid)) else { return nil }
        scene.id = uuid
        return scene
    }

    func saveScene(_ scene: SceneSettings) {
        guard !configFileIsBroken else {
            AppLog.persist.error("Refusing to save scene — config.json failed to decode.")
            return
        }
        save(scene, to: sceneFileURL(for: scene.id))
    }

    func deleteScene(uuid: UUID) {
        guard !configFileIsBroken else { return }
        try? FileManager.default.removeItem(at: sceneFileURL(for: uuid))
    }

    /// Removes any `scene-*.json` files whose UUIDs are NOT in the supplied
    /// set. Called after structural changes so the on-disk directory matches
    /// the config.json registry.
    func deleteScenesNotIn(_ keep: Set<UUID>) {
        guard !configFileIsBroken else { return }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: scenesDirURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in urls {
            guard url.pathExtension == "json" else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.hasPrefix("scene-"),
                  let uuid = UUID(uuidString: String(stem.dropFirst("scene-".count)))
            else { continue }
            if !keep.contains(uuid) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Generic load / save

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            AppLog.persist.error("""
                Failed to load \(url.lastPathComponent, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
            return nil
        }
    }

    /// Canonical on-disk JSON encoding: pretty-printed, sorted keys, doubles
    /// rounded to 4 decimals. Also used verbatim for preset export so a
    /// shared file is byte-identical to its internal counterpart.
    static func encodeJSONForDisk<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let raw = try encoder.encode(value)
        // JSONEncoder writes doubles with the "shortest decimal that
        // round-trips" rule — so values like `0.1 + 0.05 == 0.15000…002`
        // get the full IEEE-754 string. Post-process: regex-find every
        // decimal literal, round to 4 decimals, emit the shortest repr.
        guard var text = String(data: raw, encoding: .utf8) else {
            throw NSError(
                domain: "XDGStorage", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "UTF-8 decode of encoded JSON failed"]
            )
        }
        text = roundDoublesInJSONText(text)
        guard let cleaned = text.data(using: .utf8) else {
            throw NSError(
                domain: "XDGStorage", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "UTF-8 re-encode after rounding failed"]
            )
        }
        return cleaned
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Self.encodeJSONForDisk(value)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.persist.error("""
                Failed to save \(url.lastPathComponent, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
        }
    }

    // MARK: - Double-rounding pass

    private static let doubleLiteralRegex: NSRegularExpression = {
        // Matches a JSON number with a decimal point and optional exponent.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"-?\d+\.\d+(?:[eE][-+]?\d+)?"#)
    }()

    static func roundDoublesInJSONText(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var result = ""
        var lastUpper = text.startIndex
        doubleLiteralRegex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match, let matchRange = Range(match.range, in: text) else { return }
            result += text[lastUpper..<matchRange.lowerBound]
            let token = String(text[matchRange])
            if let d = Double(token) {
                result += formatDouble((d * 10000).rounded() / 10000)
            } else {
                result += token
            }
            lastUpper = matchRange.upperBound
        }
        result += text[lastUpper..<text.endIndex]
        return result
    }

    private static func formatDouble(_ value: Double) -> String {
        guard !value.isNaN, !value.isInfinite else { return "0" }
        if value.truncatingRemainder(dividingBy: 1) == 0 && abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    // MARK: - Migrations

    private var legacySandboxPlistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(AppConstants.bundleId)
            .appendingPathComponent("Data/Library/Preferences")
            .appendingPathComponent("\(AppConstants.bundleId).plist")
    }

    /// Old transitional single-file scenes location (briefly used between
    /// "everything in config.json" and "scenes/ directory").
    private var legacyCombinedScenesFileURL: URL {
        scenesDirURL.deletingLastPathComponent().appendingPathComponent("scenes.json")
    }

    private func runMigrationsIfNeeded() {
        // If config.json already has a scenes list we're on the current
        // layout and nothing to migrate.
        if let cfg = loadConfig(), !cfg.scenes.isEmpty { return }

        // Source 4: per-scene files named after scene name (last transitional
        // layout). Adopt: rename each to scene-<uuid>.json, build config.scenes.
        if hasPerNameSceneFiles() {
            migrateFromPerNameSceneFiles()
            return
        }

        // Source 3: transitional single scenes.json with `{ "scenes": [...] }`.
        if FileManager.default.fileExists(atPath: legacyCombinedScenesFileURL.path) {
            migrateFromCombinedScenesFile()
            return
        }

        // Source 2: even older combined config.json with `scenes` key inline.
        if FileManager.default.fileExists(atPath: configFileURL.path),
           let raw = try? Data(contentsOf: configFileURL),
           let tree = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           tree["scenes"] is [Any] {
            migrateFromCombinedConfig(tree)
            return
        }

        // Source 1: pre-XDG sandbox container plist.
        if FileManager.default.fileExists(atPath: legacySandboxPlistURL.path),
           let plist = NSDictionary(contentsOf: legacySandboxPlistURL) as? [String: Any] {
            migrateFromSandboxPlist(plist)
            return
        }
    }

    private func hasPerNameSceneFiles() -> Bool {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: scenesDirURL, includingPropertiesForKeys: nil
        ) else { return false }
        return urls.contains { url in
            let stem = url.deletingPathExtension().lastPathComponent
            return url.pathExtension == "json" && !stem.hasPrefix("scene-")
        }
    }

    private func migrateFromPerNameSceneFiles() {
        AppLog.persist.info("Migrating per-name scene files → scene-<uuid>.json layout…")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: scenesDirURL, includingPropertiesForKeys: nil
        ) else { return }

        var sceneIDs: [UUID] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where url.pathExtension == "json" {
            let stem = url.deletingPathExtension().lastPathComponent
            guard !stem.hasPrefix("scene-") else { continue }   // already migrated
            guard let scene = load(SceneSettings.self, from: url) else { continue }
            scene.id = UUID()
            saveScene(scene)
            try? FileManager.default.removeItem(at: url)
            sceneIDs.append(scene.id)
        }
        writeRegistry(sceneIDs: sceneIDs, activeID: sceneIDs.first)
    }

    private func migrateFromCombinedScenesFile() {
        AppLog.persist.info("Splitting combined scenes.json into per-uuid scene files…")
        guard let data = try? Data(contentsOf: legacyCombinedScenesFileURL),
              let tree = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scenesAny = tree["scenes"],
              let scenesData = try? JSONSerialization.data(withJSONObject: scenesAny),
              let scenes = try? JSONDecoder().decode([SceneSettings].self, from: scenesData)
        else { return }

        var ids: [UUID] = []
        for scene in scenes {
            scene.id = UUID()
            saveScene(scene)
            ids.append(scene.id)
        }
        writeRegistry(sceneIDs: ids, activeID: ids.first)
        // Leave legacy file on disk for rollback safety.
    }

    private func migrateFromCombinedConfig(_ tree: [String: Any]) {
        AppLog.persist.info("Extracting scenes from combined config.json…")
        guard let scenesAny = tree["scenes"],
              let scenesData = try? JSONSerialization.data(withJSONObject: scenesAny),
              let scenes = try? JSONDecoder().decode([SceneSettings].self, from: scenesData)
        else { return }

        var ids: [UUID] = []
        for scene in scenes {
            scene.id = UUID()
            saveScene(scene)
            ids.append(scene.id)
        }
        writeRegistry(sceneIDs: ids, activeID: ids.first)
        // config.json's old `scenes` key gets dropped on next save because
        // AppConfig's Codable no longer knows about a different shape.
    }

    private func migrateFromSandboxPlist(_ plist: [String: Any]) {
        AppLog.persist.info("Migrating from legacy sandbox container plist…")

        let motionStyleRaw = plist["motionStyle"] as? String ?? MotionStyle.snappy.rawValue
        let motionStyle = MotionStyle(rawValue: motionStyleRaw) ?? .snappy

        let displayIDsRaw = plist["enabledDisplayIDs"] as? [Int64] ?? []
        let displayIDs = displayIDsRaw.map { CGDirectDisplayID($0) }

        var scenes: [SceneSettings] = []
        if let scenesData = plist["visualizerScenes"] as? Data {
            scenes = (try? JSONDecoder().decode([SceneSettings].self, from: scenesData)) ?? []
        }

        // Legacy active ref was a UUID matching the old SceneSettings.id stored
        // in the plist's scenes JSON. After decode the in-memory scenes carry
        // those original UUIDs (decoder falls back to generated UUID if absent
        // — but the sandbox-era data has them), so map activeSceneID across.
        var activeID: UUID? = scenes.first?.id
        if let idStr = plist["activeSceneID"] as? String,
           let uuid = UUID(uuidString: idStr),
           scenes.contains(where: { $0.id == uuid }) {
            activeID = uuid
        }

        var ids: [UUID] = []
        for scene in scenes {
            saveScene(scene)
            ids.append(scene.id)
        }

        let initialized = plist["enabledDisplayIDsInitialized"] as? Bool ?? false

        saveConfig(AppConfig(
            version: 1,
            motionStyle: motionStyle,
            enabledDisplayIDs: displayIDs,
            scenes: ids,
            activeScene: activeID
        ))
        saveState(AppState(version: 1, enabledDisplayIDsInitialized: initialized))
        AppLog.persist.info("""
            Migration done. scenes=\(scenes.count, privacy: .public) \
            active=\(activeID?.uuidString ?? "(none)", privacy: .public)
            """)
    }

    /// Writes (or rewrites) config.json with the supplied scene registry,
    /// preserving any other config fields that already live on disk.
    private func writeRegistry(sceneIDs: [UUID], activeID: UUID?) {
        var config = loadConfig() ?? AppConfig()
        config.scenes = sceneIDs
        config.activeScene = activeID
        saveConfig(config)
    }
}

// MARK: - Per-preset files (UUID-keyed)
//
// Presets reuse SceneSettings' wire format and mirror the scenes/ layout,
// but deliberately have no registry in config.json (no order/active
// semantics — the directory IS the library). That independence also means
// none of these are gated on `configFileIsBroken`.

extension XDGStorage {

    func presetFileURL(for uuid: UUID) -> URL {
        presetsDirURL.appendingPathComponent("preset-\(uuid.uuidString).json")
    }

    func loadPreset(uuid: UUID) -> SceneSettings? {
        guard let preset = load(SceneSettings.self, from: presetFileURL(for: uuid)) else { return nil }
        preset.id = uuid
        return preset
    }

    func savePreset(_ preset: SceneSettings) {
        save(preset, to: presetFileURL(for: preset.id))
    }

    func deletePreset(uuid: UUID) {
        try? FileManager.default.removeItem(at: presetFileURL(for: uuid))
    }

    func listPresetUUIDs() -> [UUID] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: presetsDirURL,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.hasPrefix("preset-") else { return nil }
            return UUID(uuidString: String(stem.dropFirst("preset-".count)))
        }
    }
}
