//
//  BorderTrailRendererRegistry.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/2.
//

import AppKit

class BorderTrailRendererRegistry {
    static let shared = BorderTrailRendererRegistry()
    private var renderers: [NSScreen: BorderTrailRenderer] = [:]
    private let lock = NSLock()

    func register(_ renderer: BorderTrailRenderer, for screen: NSScreen) {
        lock.lock()
        renderers[screen] = renderer
        lock.unlock()
    }

    func renderer(for screen: NSScreen) -> BorderTrailRenderer? {
        lock.lock()
        defer { lock.unlock() }
        return renderers[screen]
    }

    // BorderEffect 用這個，找自己所在 scene 對應的 renderer
    func rendererForMainScreen() -> BorderTrailRenderer? {
        renderer(for: NSScreen.screens[0])
    }
}
