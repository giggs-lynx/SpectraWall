//
//  AppDelegate.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SwiftUI
import SpriteKit
import Combine
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    private var desktopWindows: [NSWindow] = []
    private var monitor: AudioProcessMonitor?
    private var tapManager: AudioTapManager?
    private var analyzer: AudioAnalyzer?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsCancellable: AnyCancellable?
    
    private let logger = Logger(subsystem: "com.giggs.SpectraWall", category: "AppLifecycle")

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupAudioSystem()
        setupDesktopWindows()
        startObservingScreenChanges()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Ensure data is persisted before the app closes
        VisualizerSceneManager.shared.saveImmediately()
    }

    // MARK: - Menu Bar & UI
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: AppConstants.appName)
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: PopoverView())
        popover.behavior = .transient
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Audio Logic
    private func setupAudioSystem() {
        analyzer = AudioAnalyzer(fftSize: 4096, binCount: 96)
        
        settingsCancellable = AppSettings.shared.$audioSource
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                self?.switchAudioSource(to: source)
            }
        
        startAudioMonitor()
    }

    private func switchAudioSource(to source: AudioSource) {
        tapManager?.stop()
        tapManager = nil
        
        switch source {
        case .global:
            startGlobalTap()
        case .app(let app):
            startTap(for: app)
        }
    }

    private func startAudioMonitor() {
        monitor = AudioProcessMonitor()
        monitor?.onAppsChanged = { [weak self] apps in
            guard let self else { return }
            AppSettings.shared.activeApps = apps
            self.handleAudioSourceAutoSwitch(apps: apps)
        }
        monitor?.start()
    }

    private func handleAudioSourceAutoSwitch(apps: [AudioApp]) {
        switch AppSettings.shared.audioSource {
        case .global:
            if tapManager == nil { startGlobalTap() }
        case .app(let selectedApp):
            let isSelectedAppActive = apps.contains { $0.bundleID == selectedApp.bundleID }

            if !isSelectedAppActive {
                tapManager?.stop()
                tapManager = nil
                AudioDataBus.shared.resetPublisher.send()
                AudioDataBus.shared.amplitudePublisher.send(0)
            } else if tapManager == nil {
                if let match = apps.first(where: { $0.bundleID == selectedApp.bundleID }) {
                    AppSettings.shared.audioSource = .app(match)
                    startTap(for: match)
                }
            }
        }
    }

    private func startGlobalTap() {
        setupTap { $0.startGlobal() }
    }

    private func startTap(for app: AudioApp) {
        setupTap { $0.start(app: app) }
    }

    private func setupTap(_ activationBlock: (AudioTapManager) -> Void) {
        let tap = AudioTapManager()
        tap.onAudioData = { [weak self] left, right in
            guard let self, let bins = self.analyzer?.analyze(left: left, right: right) else { return }
            let bassAmplitude = Float(bins.left.prefix(8).reduce(0, +) + bins.right.prefix(8).reduce(0, +)) / 16
            AudioDataBus.shared.spectrumPublisher.send(bins)
            AudioDataBus.shared.amplitudePublisher.send(bassAmplitude)
        }
        activationBlock(tap)
        tapManager = tap
    }

    // MARK: - Windows Management
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

        let scene = VisualizerScene(size: screen.frame.size)
        skView.presentScene(scene)

        window.contentView = skView
        return window
    }

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
