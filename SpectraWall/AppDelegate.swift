//
//  AppDelegate.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import AppKit
import SpriteKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var desktopWindows: [NSWindow] = []
    var monitor: AudioProcessMonitor?
    var audioTap: CoreAudioTap?
    var analyzer: AudioAnalyzer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupDesktopWindows()
        startObservingScreenChanges()
        
        monitor = AudioProcessMonitor()
        monitor?.onAppsChanged = { [weak self] apps in
            print("Active audio apps:")
            apps.forEach { print("  \($0.name) — \($0.bundleID ?? "no bundle ID") — objectIDs: \($0.objectIDs)") }

            // 抓第一個 app 測試
            if let first = apps.first, self?.audioTap == nil {
                let tap = CoreAudioTap()
                tap.onAudioData = { [weak self] samples in
                    guard let self, let bins = self.analyzer?.analyze(samples) else { return }
                    let amplitude = samples.map { abs($0) }.max() ?? 0
                    AudioDataBus.shared.spectrumPublisher.send(bins)
                    AudioDataBus.shared.amplitudePublisher.send(amplitude)
                }
                tap.start(app: first)
                self?.audioTap = tap
            }
        }
        monitor?.start()
        
        analyzer = AudioAnalyzer(fftSize: 1024, binCount: 32)
    }

    // MARK: - 視窗建立

    private func setupDesktopWindows() {
        desktopWindows.forEach { $0.close() }
        desktopWindows = []

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

        // 建立 SKView 填滿視窗
        let skView = SKView(frame: screen.frame)
        skView.allowsTransparency = true
        skView.scene?.backgroundColor = .clear

        // 建立測試 Scene
        let scene = TestScene(size: screen.frame.size)
        scene.backgroundColor = .clear
        skView.presentScene(scene)

        window.contentView = skView
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
