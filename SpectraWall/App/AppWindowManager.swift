//
//  AppWindowManager.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import AppKit
import SwiftUI

class AppWindowManager {
    static let shared = AppWindowManager()

    private var settingsWindow: NSWindow?

    func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsWindowView())
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.title = "SpectraWall 設定"
        window.setContentSize(NSSize(width: 1200, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
