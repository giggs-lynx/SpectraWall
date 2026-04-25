//
//  AppDelegate.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SwiftUI
import SpriteKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopWindows: [NSWindow] = []
    private var monitor: AudioProcessMonitor?
    private var audioTap: CoreAudioTap?
    private var analyzer: AudioAnalyzer?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsCancellable: AnyCancellable?


    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        settingsCancellable = AppSettings.shared.$audioSource
            .dropFirst()  // 跳過初始值
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                self?.switchAudioSource(to: source)
            }
        
        analyzer = AudioAnalyzer(fftSize: 4096, binCount: 96)
        setupDesktopWindows()
        startObservingScreenChanges()
        startAudioMonitor()
    }
    
    private func switchAudioSource(to source: AudioSource) {
        audioTap?.stop()
        audioTap = nil

        switch source {
        case .global:
            startGlobalTap()
        case .app(let app):
            startTap(for: app)
        }
    }
    
    private func startGlobalTap() {
        let tap = CoreAudioTap()
        tap.onAudioData = { [weak self] samples in
            guard let self, let bins = self.analyzer?.analyze(samples) else { return }
            let bassAmplitude = Float(bins.prefix(8).reduce(0, +)) / 8
            AudioDataBus.shared.spectrumPublisher.send(bins)
            AudioDataBus.shared.amplitudePublisher.send(bassAmplitude)
        }
        tap.startGlobal()
        audioTap = tap
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SpectraWall")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: SettingsView())
        popover.behavior = .transient
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - 音訊

    private func startAudioMonitor() {
        monitor = AudioProcessMonitor()
        monitor?.onAppsChanged = { [weak self] apps in
            guard let self else { return }
            AppSettings.shared.activeApps = apps

            guard self.audioTap == nil else { return }

            switch AppSettings.shared.audioSource {
            case .global:
                self.startGlobalTap()
            case .app(let selectedApp):
                if let match = apps.first(where: { $0.pid == selectedApp.pid }) {
                    self.startTap(for: match)
                }
            }
        }
        monitor?.start()

        switch AppSettings.shared.audioSource {
        case .global:
            startGlobalTap()
        case .app:
            break
        }
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
