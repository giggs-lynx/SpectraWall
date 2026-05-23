//
//  EffectRegistry.swift
//  SpectraWall
//
//  Single source of truth for which effect kinds exist. AppDelegate calls
//  `bootstrap()` once at launch; everything else queries the registry.
//
//  To add a fourth effect kind:
//    1. Add an `EffectType` static member (the rawValue is the on-disk key).
//    2. Implement an `Effect`-conforming class (typically by subclassing
//       BaseEffect) and expose a `static let descriptor`.
//    3. Append one `register(...)` call in `bootstrap()`.
//

import Foundation

enum EffectRegistry {
    static private(set) var all: [EffectType: EffectDescriptor] = [:]

    /// EffectType values currently registered, sorted by renderOrder so UI
    /// pickers and the renderer's draw loop see the same canonical order.
    static var allTypes: [EffectType] {
        all.values.sorted { $0.renderOrder < $1.renderOrder }.map(\.type)
    }

    static func descriptor(for type: EffectType) -> EffectDescriptor? {
        all[type]
    }

    static func register(_ descriptor: EffectDescriptor) {
        all[descriptor.type] = descriptor
    }

    /// Idempotent. Called once at app startup.
    static func bootstrap() {
        guard all.isEmpty else { return }
        register(SpectrumEffect.descriptor)
        register(OrbEffect.descriptor)
        register(BorderEffect.descriptor)
    }
}
