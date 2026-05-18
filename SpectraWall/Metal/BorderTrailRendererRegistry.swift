//
//  BorderTrailRendererRegistry.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/2.
//

import AppKit

class EffectsRendererRegistry {
    static let shared = EffectsRendererRegistry()
    private var renderers: [NSScreen: EffectsRenderer] = [:]
    private let lock = NSLock()

    func register(_ renderer: EffectsRenderer, for screen: NSScreen) {
        lock.lock()
        renderers[screen] = renderer
        lock.unlock()
    }

    func renderer(for screen: NSScreen) -> EffectsRenderer? {
        lock.lock()
        defer { lock.unlock() }
        return renderers[screen]
    }

    func rendererForMainScreen() -> EffectsRenderer? {
        renderer(for: NSScreen.screens[0])
    }
}

// MARK: - Backward compatibility typealias
// Remove after all call sites are updated to EffectsRendererRegistry.
typealias BorderTrailRendererRegistry = EffectsRendererRegistry
