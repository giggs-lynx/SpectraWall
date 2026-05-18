//
//  AppDelegate.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SwiftUI
import OSLog
import MetalKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Types

    private struct DesktopWindowSet {
        let window: NSWindow
        let mtkView: MTKView
        let coordinator: EffectsCoordinator
    }

    // MARK: - Properties

    private var windowSets: [DesktopWindowSet] = []
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var trailRenderers: [NSScreen: BorderTrailRenderer] = [:]
    private var cancellables = Set<AnyCancellable>()

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
            let icon = NSImage(named: "AppIcon")
            icon?.size = NSSize(width: 18, height: 18)
            button.image = icon
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

    private func activeScreens() -> [NSScreen] {
        let enabled = AppSettings.shared.enabledDisplayIDs
        return NSScreen.screens.filter { enabled.contains($0.displayID) }
    }

    private func setupDesktopWindows() {
        let oldSets = windowSets
        windowSets = []
        trailRenderers = [:]

        // Stop render loops and hide immediately (synchronous).
        for set in oldSets {
            set.mtkView.isPaused = true
            set.window.orderOut(nil)
        }

        // Create new windows on the updated screen list.
        for screen in activeScreens() {
            if let set = makeDesktopWindowSet(for: screen) {
                set.window.orderFront(nil)
                windowSets.append(set)
            }
        }

        // Defer the actual dealloc by one run loop so any CVDisplayLink
        // callbacks already in flight on a background thread can finish
        // before the objects they reference are freed.
        DispatchQueue.main.async { _ = oldSets }
    }

    private func effectiveFrame(for screen: NSScreen) -> CGRect {
        screen.visibleFrame
    }

    private func makeDesktopWindowSet(for screen: NSScreen) -> DesktopWindowSet? {
        let frame = effectiveFrame(for: screen)
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.animationBehavior = .none

        let size = frame.size
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))
        containerView.wantsLayer = true

        // Match the display's native refresh rate so every frame aligns with VSync.
        // Capping ProMotion (120 Hz) to 60 fps causes judder because frames land on
        // alternating VSync pairs unevenly. Time-based smoothing handles any frame rate.
        let nativeFPS = screen.maximumFramesPerSecond

        // MTKView — sole render surface after full Metal migration
        let mtkView = MTKView(frame: NSRect(origin: .zero, size: size))
        mtkView.layer?.isOpaque = false
        mtkView.layer?.backgroundColor = .clear
        mtkView.wantsLayer = true
        guard let renderer = BorderTrailRenderer(mtkView: mtkView) else { return nil }

        mtkView.delegate = renderer
        trailRenderers[screen] = renderer
        BorderTrailRendererRegistry.shared.register(renderer, for: screen)

        let scale = screen.backingScaleFactor
        renderer.setBackingScaleFactor(scale)
        // Pin the shader's vertex normalization basis to the scene size in
        // points. This is independent of the Metal drawable size, which
        // AppKit may resize at any time.
        renderer.setSceneSize(size)
        let drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        mtkView.drawableSize = drawableSize
        // Override the 60 fps default set inside BorderTrailRenderer.init.
        mtkView.preferredFramesPerSecond = nativeFPS

        containerView.addSubview(mtkView)

        // Coordinator manages all effect lifecycles; must be created AFTER
        // the renderer is registered so findRenderer(for:) succeeds.
        let coordinator = EffectsCoordinator(size: size, screen: screen)

        window.contentView = containerView
        return DesktopWindowSet(window: window, mtkView: mtkView, coordinator: coordinator)
    }

    private func startObservingScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupDesktopWindows()
        }

        AppSettings.shared.$enabledDisplayIDs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setupDesktopWindows() }
            .store(in: &cancellables)
    }
}

// MARK: - NSScreen helpers

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
