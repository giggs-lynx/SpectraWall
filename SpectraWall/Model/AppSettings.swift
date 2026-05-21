//
//  AppSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI
import Combine

// MARK: - Models
enum AudioSource: Equatable {
    case global
    case app(AudioApp)

    var displayName: String {
        switch self {
        case .global: return "Global（所有音訊）"
        case .app(let app): return app.name
        }
    }
}

extension AudioApp: Equatable {
    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.pid == rhs.pid
    }
}

// MARK: - AppSettings
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var audioSource: AudioSource = .global
    @Published var activeApps: [AudioApp] = []
    @Published var lastSelectedApp: AudioApp?

    /// Display IDs of screens where SpectraWall should render. Empty = no screens.
    @Published var enabledDisplayIDs: Set<CGDirectDisplayID> {
        didSet {
            UserDefaults.standard.set(Array(enabledDisplayIDs).map { Int64($0) }, forKey: "enabledDisplayIDs")
        }
    }

    /// Global animation style. Affects how Orb and Spectrum chase their audio-driven
    /// targets between frames. Per-effect override would be over-engineering for
    /// what is really a feel preference.
    @Published var motionStyle: MotionStyle {
        didSet { UserDefaults.standard.set(motionStyle.rawValue, forKey: "motionStyle") }
    }

    private init() {
        let initialized = UserDefaults.standard.bool(forKey: "enabledDisplayIDsInitialized")
        if initialized {
            let stored = UserDefaults.standard.array(forKey: "enabledDisplayIDs") as? [Int64] ?? []
            enabledDisplayIDs = Set(stored.map { CGDirectDisplayID($0) })
        } else {
            // First launch: enable only the primary display by default.
            let initial: Set<CGDirectDisplayID> = [CGMainDisplayID()]
            enabledDisplayIDs = initial
            UserDefaults.standard.set(Array(initial).map { Int64($0) }, forKey: "enabledDisplayIDs")
            UserDefaults.standard.set(true, forKey: "enabledDisplayIDsInitialized")
        }
        let storedMotion = UserDefaults.standard.string(forKey: "motionStyle") ?? MotionStyle.snappy.rawValue
        motionStyle = MotionStyle(rawValue: storedMotion) ?? .snappy
    }
}
