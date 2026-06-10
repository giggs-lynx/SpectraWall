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
        didSet { writeConfig { $0.enabledDisplayIDs = enabledDisplayIDs.sorted() } }
    }

    /// Global animation style. Affects how Orb and Spectrum chase their audio-driven
    /// targets between frames. Per-effect override would be over-engineering for
    /// what is really a feel preference.
    @Published var motionStyle: MotionStyle {
        didSet { writeConfig { $0.motionStyle = motionStyle } }
    }

    /// 4× MSAA toggle. Renderers are rebuilt when this changes.
    @Published var msaaEnabled: Bool {
        didSet { writeConfig { $0.msaaEnabled = msaaEnabled } }
    }

    /// Global debug overlay master switch. AppDelegate fans the value out to all
    /// active renderers — no renderer rebuild needed (cheap, unlike MSAA).
    @Published var debugEnabled: Bool {
        didSet { writeConfig { $0.debugOverlayEnabled = debugEnabled } }
    }

    /// Which effect types draw their wireframe while the master is on. Effects
    /// outside the set keep rendering normally. Same fan-out path as
    /// `debugEnabled`. Persisted sorted for a stable config.json.
    @Published var debugTypes: Set<EffectType> {
        didSet { writeConfig { $0.debugTypes = debugTypes.sorted { $0.rawValue < $1.rawValue } } }
    }

    private init() {
        let config = XDGStorage.shared.loadConfig() ?? AppConfig()
        let state = XDGStorage.shared.loadState() ?? AppState()

        if state.enabledDisplayIDsInitialized {
            enabledDisplayIDs = Set(config.enabledDisplayIDs)
        } else {
            // First launch: enable only the primary display by default.
            enabledDisplayIDs = [CGMainDisplayID()]
        }
        motionStyle = config.motionStyle
        msaaEnabled = config.msaaEnabled
        debugEnabled = config.debugOverlayEnabled
        debugTypes = config.debugTypes.map(Set.init) ?? Set(EffectRegistry.allTypes)

        // After all stored properties are initialized we can safely persist
        // any first-launch defaults.
        if !state.enabledDisplayIDsInitialized {
            writeConfig { $0.enabledDisplayIDs = enabledDisplayIDs.sorted() }
            writeState { $0.enabledDisplayIDsInitialized = true }
        }
    }

    /// Mutate AppConfig on disk. Reads current value (so we don't clobber other
    /// owners' fields like `scenes` written by VisualizerSceneManager), applies
    /// the mutation, writes back atomically. XDGStorage.saveConfig is a no-op
    /// while config.json is broken, so this naturally degrades to read-only.
    private func writeConfig(_ mutate: (inout AppConfig) -> Void) {
        var config = XDGStorage.shared.loadConfig() ?? AppConfig()
        mutate(&config)
        XDGStorage.shared.saveConfig(config)
    }

    private func writeState(_ mutate: (inout AppState) -> Void) {
        var state = XDGStorage.shared.loadState() ?? AppState()
        mutate(&state)
        XDGStorage.shared.saveState(state)
    }
}
