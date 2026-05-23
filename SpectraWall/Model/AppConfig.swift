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
}
