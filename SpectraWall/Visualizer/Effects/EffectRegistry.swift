//
//  EffectRegistry.swift
//  SpectraWall
//
//  Single source of truth for which effect kinds exist. The registry is
//  populated exactly once via the Swift `static let` once-init guarantee on
//  `_bootstrapped`; any access to `descriptor(for:)` / `allTypes` / `all`
//  triggers it. AppDelegate calls `bootstrap()` explicitly during launch
//  for ordering clarity, but the lazy fallback covers cases where
//  SwiftUI evaluates a Scene body (e.g. the Settings window) before
//  `applicationDidFinishLaunching` fires — that ordering bug previously
//  caused all `LayerSettings` decoded during that early phase to fall
//  back to `SpectrumSettings.defaults` regardless of their stored
//  `effectType`.
//
//  To add a fourth effect kind:
//    1. Add an `EffectType` static member (the rawValue is the on-disk key).
//    2. Implement an `Effect`-conforming class (typically by subclassing
//       BaseEffect) and expose a `static let descriptor`.
//    3. Append one `register(...)` call inside `_bootstrapped`.
//

import Foundation

enum EffectRegistry {
    private(set) static var all: [EffectType: EffectDescriptor] = [:]

    /// Lazily registered once on first access. Swift's static-let
    /// initialisation is dispatch_once-equivalent, so this is thread-safe
    /// and idempotent without an extra lock.
    private static let _bootstrapped: Void = {
        register(SpectrumEffect.descriptor)
        register(OrbEffect.descriptor)
        register(BorderEffect.descriptor)
    }()

    /// EffectType values currently registered, sorted by renderOrder so UI
    /// pickers and the renderer's draw loop see the same canonical order.
    static var allTypes: [EffectType] {
        _ = _bootstrapped
        return all.values.sorted { $0.renderOrder < $1.renderOrder }.map(\.type)
    }

    static func descriptor(for type: EffectType) -> EffectDescriptor? {
        _ = _bootstrapped
        return all[type]
    }

    static func register(_ descriptor: EffectDescriptor) {
        all[descriptor.type] = descriptor
    }

    /// Explicit bootstrap entry point. Triggers the once-init `_bootstrapped`
    /// closure; idempotent. AppDelegate calls this at launch for clarity,
    /// but every other code path also triggers it implicitly through
    /// `descriptor(for:)` or `allTypes`.
    static func bootstrap() {
        _ = _bootstrapped
    }
}
