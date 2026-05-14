//
//  AppDelegate.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SwiftUI
import SpriteKit
import OSLog
import MetalKit

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var desktopWindows: [NSWindow] = []
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var trailRenderers: [NSScreen: BorderTrailRenderer] = [:]

    private let logger = Logger(subsystem: AppConstants.bundleId, category: "AppLifecycle")

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        AudioEngine.shared.start()
        setupDesktopWindows()
        startObservingScreenChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AudioEngine.shared.stop()
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

    // MARK: - Desktop Windows

    private func setupDesktopWindows() {
        desktopWindows.forEach { $0.close() }
        desktopWindows = []

        for screen in NSScreen.screens {
            let window = makeDesktopWindow(for: screen)
            window.orderFront(nil)
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

        let size = screen.frame.size
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))
        containerView.wantsLayer = true

        // Match the display's native refresh rate so every frame aligns with VSync.
        // Capping ProMotion (120 Hz) to 60 fps causes judder because frames land on
        // alternating VSync pairs unevenly. Time-based smoothing handles any frame rate.
        let nativeFPS = screen.maximumFramesPerSecond

        // SKView
        let skView = SKView(frame: NSRect(origin: .zero, size: size))
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = nativeFPS
        let scene = VisualizerScene(size: size)
        scene.screen = screen
        skView.presentScene(scene)
        containerView.addSubview(skView)

        // MTKView
        let mtkView = MTKView(frame: NSRect(origin: .zero, size: size))
        mtkView.layer?.isOpaque = false
        mtkView.layer?.backgroundColor = .clear
        mtkView.wantsLayer = true
        if let renderer = BorderTrailRenderer(mtkView: mtkView) {
            mtkView.delegate = renderer
            trailRenderers[screen] = renderer
            BorderTrailRendererRegistry.shared.register(renderer, for: screen)

            let scale = screen.backingScaleFactor
            let drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
            mtkView.drawableSize = drawableSize
            renderer.mtkView(mtkView, drawableSizeWillChange: drawableSize)
            // Override the 60 fps default set inside BorderTrailRenderer.init.
            mtkView.preferredFramesPerSecond = nativeFPS
        }
        containerView.addSubview(mtkView)

        window.contentView = containerView
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
