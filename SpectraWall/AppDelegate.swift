//
//  AppDelegate.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var desktopWindows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupDesktopWindows()
        startObservingScreenChanges()
    }

    // MARK: - 視窗建立

    private func setupDesktopWindows() {
        // 先清掉舊的
        desktopWindows.forEach { $0.close() }
        desktopWindows = []

        // 每個螢幕建一個視窗
        for screen in NSScreen.screens {
            let window = makeDesktopWindow(for: screen)
            window.makeKeyAndOrderFront(nil)
            desktopWindows.append(window)
        }
    }

    private func makeDesktopWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        return window
    }

    // MARK: - 多螢幕監聽

    private func startObservingScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupDesktopWindows()
        }
    }
}
