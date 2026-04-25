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
    private var desktopWindows: [NSWindow] = []
    private var monitor: AudioProcessMonitor?
    private var audioTap: CoreAudioTap?
    private var analyzer: AudioAnalyzer?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        analyzer = AudioAnalyzer(fftSize: 4096, binCount: 96)
        setupDesktopWindows()
        startObservingScreenChanges()
        startAudioMonitor()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SpectraWall")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        // 之後實作
        print("open settings")
    }

    // MARK: - 音訊

    private func startAudioMonitor() {
        monitor = AudioProcessMonitor()
        monitor?.onAppsChanged = { [weak self] apps in
            guard let self, self.audioTap == nil, let first = apps.first else { return }
            self.startTap(for: first)
        }
        monitor?.start()
    }

    private func startTap(for app: AudioApp) {
        let tap = CoreAudioTap()
        tap.onAudioData = { [weak self] samples in
            guard let self, let bins = self.analyzer?.analyze(samples) else { return }
            let bassAmplitude = Float(bins.prefix(8).reduce(0, +)) / 8
            AudioDataBus.shared.spectrumPublisher.send(bins)
            AudioDataBus.shared.amplitudePublisher.send(bassAmplitude)
        }
        tap.start(app: app)
        audioTap = tap
    }

    // MARK: - 視窗

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

        let skView = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        skView.allowsTransparency = true

        let scene = SpectrumScene(size: screen.frame.size)
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
