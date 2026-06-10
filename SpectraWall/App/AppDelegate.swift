//
//  AppDelegate.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SwiftUI
import Metal
import OSLog
import QuartzCore
import Combine

extension Notification.Name {
    static let showAboutWindow = Notification.Name("com.spectrawall.showAboutWindow")
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    // MARK: - Types

    private struct DesktopWindowSet {
        let window: NSWindow
        let metalView: EffectsHostView
        let renderer: EffectRenderer
        let coordinator: EffectsCoordinator
    }

    // MARK: - Properties

    private var windowSets: [DesktopWindowSet] = []
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var aboutWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var renderWatchdog: DispatchSourceTimer?
    /// Event monitors that auto-close the popover when the user clicks outside.
    /// NSPopover's `.transient` behavior doesn't fire reliably for an LSUIElement app
    /// whose other windows are at `desktopWindow` level — we drive it ourselves.
    private var popoverGlobalMonitor: Any?
    private var popoverLocalMonitor: Any?
    private var iconCancellable: AnyCancellable?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register every effect kind with EffectRegistry before the renderer
        // tries to compile pipelines from the registry.
        EffectRegistry.bootstrap()

        setupMenuBar()
        AudioEngine.shared.start()
        setupDesktopWindows(reason: "appLaunch")
        startObservingScreenChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        renderWatchdog?.cancel()
        AudioEngine.shared.stop()
        VisualizerSceneManager.shared.saveImmediately()
    }

    // MARK: - Menu Bar & UI

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = drawMenuBarIcon(IconSpectrum.restingHeights)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Drive the menu-bar icon's bars from live audio. Monitor runs for the
        // app's lifetime; it stops emitting once a quiet source settles, so this
        // only redraws while sound is actually playing.
        AudioActivityMonitor.shared.start()
        iconCancellable = AudioActivityMonitor.shared.$iconBars
            .sink { [weak self] heights in
                self?.statusItem?.button?.image = self?.drawMenuBarIcon(heights)
            }

        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: PopoverView())
        popover.behavior = .transient
        popover.delegate = self
        self.popover = popover

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showAboutWindow),
            name: .showAboutWindow,
            object: nil
        )
    }

    @objc private func showAboutWindow() {
        popover?.performClose(nil)

        if let win = aboutWindow {
            win.center()
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: AboutView())
        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.titled, .closable]
        win.title = String(localized: "About SpectraWall")
        win.isReleasedWhenClosed = false
        win.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow = win
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Pin the popover so Mission Control / Show Desktop / hot corners don't
            // slide it off screen with everything else.
            if let pw = popover?.contentViewController?.view.window {
                pw.collectionBehavior.insert([.stationary, .canJoinAllSpaces])
            }
            popover?.contentViewController?.view.window?.makeKey()
            installPopoverOutsideClickMonitors()
        }
    }

    /// Install global + local NSEvent monitors so clicking anywhere outside the
    /// popover closes it. Global monitor catches clicks in other apps (Finder
    /// desktop, etc.); local monitor catches clicks in our own windows
    /// (e.g. Settings panel after opening it from the popover).
    private func installPopoverOutsideClickMonitors() {
        removePopoverOutsideClickMonitors()
        popoverGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.popover?.performClose(nil)
        }
        popoverLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            // Don't close if the click landed inside the popover itself.
            if event.window !== self.popover?.contentViewController?.view.window {
                self.popover?.performClose(nil)
            }
            return event
        }
    }

    private func removePopoverOutsideClickMonitors() {
        if let m = popoverGlobalMonitor { NSEvent.removeMonitor(m); popoverGlobalMonitor = nil }
        if let m = popoverLocalMonitor { NSEvent.removeMonitor(m); popoverLocalMonitor = nil }
    }

    // MARK: - NSPopoverDelegate

    func popoverWillClose(_ notification: Notification) {
        removePopoverOutsideClickMonitors()
    }

    // MARK: - Menu-Bar Icon Rendering

    /// Draw the icon's five spectrum bars (no background) at the given normalized
    /// heights, with the icon's pink→rose vertical gradient. Bars are bottom-aligned
    /// and capsule-capped, matching the app icon's glyph.
    private func drawMenuBarIcon(_ heights: [Double]) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let barW: CGFloat = 2
        let gap: CGFloat = 1.5
        let bottom: CGFloat = 1
        let maxH: CGFloat = 16

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let count = max(heights.count, 1)
        let totalW = CGFloat(count) * barW + CGFloat(count - 1) * gap
        let startX = (size.width - totalW) / 2

        let bars = NSBezierPath()
        for (i, h) in heights.enumerated() {
            let frac = CGFloat(max(0, min(1, h)))
            let barH = max(barW, frac * maxH)
            let x = startX + CGFloat(i) * (barW + gap)
            let rect = NSRect(x: x, y: bottom, width: barW, height: barH)
            bars.append(NSBezierPath(roundedRect: rect, xRadius: barW / 2, yRadius: barW / 2))
        }
        bars.addClip()

        let top = NSColor(srgbRed: 1.0, green: 0.64, blue: 0.71, alpha: 1)
        let rose = NSColor(srgbRed: 0.93, green: 0.30, blue: 0.40, alpha: 1)
        NSGradient(starting: rose, ending: top)?
            .draw(in: NSRect(x: 0, y: bottom, width: size.width, height: maxH), angle: 90)

        image.isTemplate = false
        return image
    }

    // MARK: - Desktop Windows

    private func activeScreens() -> [NSScreen] {
        let enabled = AppSettings.shared.enabledDisplayIDs
        return NSScreen.screens.filter { enabled.contains($0.displayID) }
    }

    private func setupDesktopWindows(reason: String = "unknown") {
        AppLog.render.info("setupDesktopWindows triggered by: \(reason, privacy: .public)")
        let oldSets = windowSets
        windowSets = []

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
        let metalView = EffectsHostView(frame: NSRect(origin: .zero, size: size))
        let sampleCount = AppSettings.shared.msaaEnabled ? 4 : 1
        guard let renderer = EffectRenderer(metalLayer: metalView.metalLayer,
                                            screen: screen,
                                            sampleCount: sampleCount) else { return nil }

        EffectRendererRegistry.shared.register(renderer, for: screen)
        renderer.setDebugEnabled(AppSettings.shared.debugEnabled)
        renderer.setDebugTypes(AppSettings.shared.debugTypes)

        let scale = screen.backingScaleFactor
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
            self?.setupDesktopWindows(reason: "didChangeScreenParameters")
        }

        // Built-in display's CAMetalDisplayLink can stop delivering callbacks
        // after sleep even when the layer/screen still look valid; rebuilding
        // the renderer is the only reliable recovery. External displays
        // usually recover on their own but get rebuilt here too for simplicity.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.setupDesktopWindows(reason: note.name.rawValue)
            }
        }

        // Pure-logging anchors for sleep/wake boundaries, on the Audio category
        // so they interleave with tap create/destroy on one log timeline. No
        // rebuild side effects — diagnosis only.
        for name in [NSWorkspace.willSleepNotification,
                     NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { note in
                AppLog.audio.info("event=system.\(note.name.rawValue, privacy: .public) t=\(CACurrentMediaTime(), privacy: .public)")
            }
        }

        AppSettings.shared.$enabledDisplayIDs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setupDesktopWindows(reason: "enabledDisplayIDs") }
            .store(in: &cancellables)

        // MSAA toggle. sampleCount is fixed at renderer init (pipelines compile
        // against it), so flipping the setting requires tearing down and
        // rebuilding every renderer.
        AppSettings.shared.$msaaEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setupDesktopWindows(reason: "msaaToggle") }
            .store(in: &cancellables)

        // Debug overlay master. Cheap fan-out to every active renderer — no
        // rebuild needed (unlike MSAA), the flag just gates the debug pass.
        AppSettings.shared.$debugEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { enabled in
                for renderer in EffectRendererRegistry.shared.allRenderers() {
                    renderer.setDebugEnabled(enabled)
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$debugTypes
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { types in
                for renderer in EffectRendererRegistry.shared.allRenderers() {
                    renderer.setDebugTypes(types)
                }
            }
            .store(in: &cancellables)

        startRenderWatchdog()
    }

    // MARK: - Render Watchdog

    private func startRenderWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5, repeating: 3)
        timer.setEventHandler { [weak self] in self?.checkRenderLoops() }
        timer.resume()
        renderWatchdog = timer
    }

    private func checkRenderLoops() {
        let now = CACurrentMediaTime()
        let stalled = windowSets.contains {
            $0.renderer.lastCallbackTime > 0 && now - $0.renderer.lastCallbackTime > 3.0
        }
        if stalled {
            AppLog.render.warning("Render watchdog: stalled display link — rebuilding renderers")
            setupDesktopWindows(reason: "watchdog")
        }
    }

}

// MARK: - NSScreen helpers

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
