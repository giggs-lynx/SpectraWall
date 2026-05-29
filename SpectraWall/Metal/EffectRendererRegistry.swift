//
//  EffectRendererRegistry.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/2.
//
//  Maps NSScreen → EffectRenderer so an effect can locate the right renderer
//  for the screen it's rendering on, without having to be wired through the
//  coordinator. Populated by AppDelegate during window setup.
//

import AppKit

class EffectRendererRegistry {
    static let shared = EffectRendererRegistry()
    private var renderers: [NSScreen: EffectRenderer] = [:]
    private let lock = NSLock()

    func register(_ renderer: EffectRenderer, for screen: NSScreen) {
        lock.lock()
        renderers[screen] = renderer
        lock.unlock()
    }

    func renderer(for screen: NSScreen) -> EffectRenderer? {
        lock.lock()
        defer { lock.unlock() }
        return renderers[screen]
    }

    func rendererForMainScreen() -> EffectRenderer? {
        renderer(for: NSScreen.screens[0])
    }

    /// Every currently-registered renderer (one per active screen). Used to
    /// fan a global setting (e.g. the debug overlay toggle) out to all screens.
    func allRenderers() -> [EffectRenderer] {
        lock.lock()
        defer { lock.unlock() }
        return Array(renderers.values)
    }
}
