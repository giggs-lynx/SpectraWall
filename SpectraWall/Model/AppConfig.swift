//
//  AppConfig.swift
//  SpectraWall
//
//  Top-level Codable for ~/.config/spectrawall/config.json.
//  Holds global preferences. Scene library lives in a separate file
//  (`scenes.json`) so individual scene tweaks don't drag the whole prefs
//  blob along, and so the file size stays readable as scenes accumulate.
//

import CoreGraphics
import Foundation

struct AppConfig: Codable {
    var version: Int = 1
    var motionStyle: MotionStyle = .snappy
    var enabledDisplayIDs: [CGDirectDisplayID] = []
    /// Ordered list of scene UUIDs. Each entry corresponds to a
    /// `scenes/scene-<uuid>.json` file. This array is both the order in the
    /// UI and the source of truth for "which scenes exist" — files on disk
    /// without a matching entry here are ignored.
    var scenes: [UUID] = []
    /// UUID of the scene the user had active last time. Nil → use first.
    var activeScene: UUID?
    /// 4× MSAA on the Metal render pass. Off keeps the single-sample fast
    /// path; on adds an offscreen multisample texture + resolve.
    var msaaEnabled: Bool = true
    /// Global debug overlay master switch. When on, effects that implement
    /// `drawDebug` paint their geometry skeleton on top via the renderer's
    /// dedicated debug pipeline.
    var debugOverlayEnabled: Bool = false

    /// Explicit memberwise init. Required because providing `init(from:)`
    /// below disables Swift's auto-synthesized memberwise init.
    init(version: Int = 1,
         motionStyle: MotionStyle = .snappy,
         enabledDisplayIDs: [CGDirectDisplayID] = [],
         scenes: [UUID] = [],
         activeScene: UUID? = nil,
         msaaEnabled: Bool = true,
         debugOverlayEnabled: Bool = false) {
        self.version = version
        self.motionStyle = motionStyle
        self.enabledDisplayIDs = enabledDisplayIDs
        self.scenes = scenes
        self.activeScene = activeScene
        self.msaaEnabled = msaaEnabled
        self.debugOverlayEnabled = debugOverlayEnabled
    }

    /// Decode with per-field fallback so older config.json files that
    /// predate newer keys still load — synthesized Codable throws on any
    /// missing key, which would flip XDGStorage into the broken-file
    /// no-write state.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        motionStyle = try c.decodeIfPresent(MotionStyle.self, forKey: .motionStyle) ?? .snappy
        enabledDisplayIDs = try c.decodeIfPresent([CGDirectDisplayID].self, forKey: .enabledDisplayIDs) ?? []
        scenes = try c.decodeIfPresent([UUID].self, forKey: .scenes) ?? []
        activeScene = try c.decodeIfPresent(UUID.self, forKey: .activeScene)
        msaaEnabled = try c.decodeIfPresent(Bool.self, forKey: .msaaEnabled) ?? true
        debugOverlayEnabled = try c.decodeIfPresent(Bool.self, forKey: .debugOverlayEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(motionStyle, forKey: .motionStyle)
        try c.encode(enabledDisplayIDs, forKey: .enabledDisplayIDs)
        try c.encode(scenes, forKey: .scenes)
        try c.encodeIfPresent(activeScene, forKey: .activeScene)
        try c.encode(msaaEnabled, forKey: .msaaEnabled)
        try c.encode(debugOverlayEnabled, forKey: .debugOverlayEnabled)
    }

    private enum CodingKeys: String, CodingKey {
        case version, motionStyle, enabledDisplayIDs, scenes, activeScene, msaaEnabled, debugOverlayEnabled
    }
}
