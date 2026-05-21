//
//  AppDelegate.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SwiftUI
import OSLog
import Metal
import QuartzCore
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Types

    private struct DesktopWindowSet {
        let window: NSWindow
        let metalView: MetalDesktopView
        let renderer: EffectsRenderer
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

        // Invalidate each renderer's CAMetalDisplayLink and hide windows. Invalidate
        // breaks the link's strong reference to the delegate and stops new callbacks;
        // a sync drain on the render queue flushes any in-flight frame.
        for set in oldSets {
            set.renderer.invalidate()
            set.window.orderOut(nil)
        }
        for set in oldSets {
            set.renderer.renderQueue.sync { }
        }

        // Create new windows on the updated screen list.
        for screen in activeScreens() {
            if let set = makeDesktopWindowSet(for: screen) {
                set.window.orderFront(nil)
                windowSets.append(set)
            }
        }

        // Keep oldSets alive one more main-runloop hop in case any stragglers
        // reference them via Unmanaged pointers.
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

        // Custom CAMetalLayer-backed NSView — replaces MTKView so the renderer's
        // draw loop runs on a private queue driven by CVDisplayLink (below)
        // instead of MTKView's internal main-thread display callback.
        let metalView = MetalDesktopView(frame: NSRect(origin: .zero, size: size))
        guard let renderer = EffectsRenderer(metalLayer: metalView.metalLayer, screen: screen) else { return nil }

        trailRenderers[screen] = renderer
        BorderTrailRendererRegistry.shared.register(renderer, for: screen)

        let scale = screen.backingScaleFactor
        renderer.setBackingScaleFactor(scale)
        renderer.setSceneSize(size)
        metalView.setLayerSize(size, scale: scale)

        containerView.addSubview(metalView)

        // The renderer creates and drives its own CAMetalDisplayLink (macOS 14+)
        // internally. No need to wire CVDisplayLink here any more.

        // Coordinator manages all effect lifecycles; must be created AFTER
        // the renderer is registered so findRenderer(for:) succeeds.
        let coordinator = EffectsCoordinator(size: size, screen: screen)

        window.contentView = containerView
        return DesktopWindowSet(window: window,
                                metalView: metalView,
                                renderer: renderer,
                                coordinator: coordinator)
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
