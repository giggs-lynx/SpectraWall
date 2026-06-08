//
//  AudioEngine.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/1.
//

import Combine
import CoreGraphics
import OSLog
import QuartzCore

class AudioEngine {
    static let shared = AudioEngine()

    private var monitor: AudioProcessMonitor?
    private var tapManager: AudioTapManager?
    private var analyzer: AudioAnalyzer?
    private var settingsCancellable: AnyCancellable?

    // Watchdog: IOProc can stall silently (sleep/wake, audio routing change, TCC
    // revoke) while AudioTapManager still holds live Core Audio objects. Without
    // observation we keep rendering the last bins forever. Poll lastSourceEmitTime
    // and force a switchSource rebuild if it goes stale.
    private var watchdogTimer: Timer?
    private var lastWatchdogRebuild: TimeInterval = 0
    private let watchdogInterval: TimeInterval = 1.0
    private let stallThreshold: TimeInterval = 2.0
    private let minRebuildInterval: TimeInterval = 5.0

    private init() {}

    // MARK: - Lifecycle

    func start() {
        analyzer = AudioAnalyzer(fftSize: 4096, binCount: 96)
        observeAudioSource()
        startMonitor()
        startWatchdog()
    }

    func stop() {
        stopWatchdog()
        tapManager?.stop()
        tapManager = nil
        monitor?.stop()
    }

    // MARK: - Source Observation

    private func observeAudioSource() {
        settingsCancellable = AppSettings.shared.$audioSource
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                self?.switchSource(to: source)
            }
    }

    private func switchSource(to source: AudioSource, reason: String = "settingsChange") {
        AppLog.audio.info("event=switchSource reason=\(reason, privacy: .public) tapMgr=\(self.tapManager == nil ? "nil" : "set", privacy: .public) t=\(CACurrentMediaTime(), privacy: .public)")
        tapManager?.stop()
        tapManager = nil

        switch source {
        case .global:
            startGlobalTap()
        case .app(let app):
            startTap(for: app)
        }
    }

    // MARK: - Monitor

    private func startMonitor() {
        monitor = AudioProcessMonitor()
        monitor?.onAppsChanged = { [weak self] apps in
            AppSettings.shared.activeApps = apps
            self?.handleAutoSwitch(apps: apps)
        }
        monitor?.start()
    }

    private func handleAutoSwitch(apps: [AudioApp]) {
        AppLog.audio.info("event=handleAutoSwitch tapMgr=\(self.tapManager == nil ? "nil" : "set", privacy: .public) appsCount=\(apps.count, privacy: .public) t=\(CACurrentMediaTime(), privacy: .public)")
        switch AppSettings.shared.audioSource {
        case .global:
            if tapManager == nil {
                AppLog.audio.info("event=autoSwitch.global.build t=\(CACurrentMediaTime(), privacy: .public)")
                startGlobalTap()
            } else {
                AppLog.audio.info("event=autoSwitch.global.skip t=\(CACurrentMediaTime(), privacy: .public)")
            }
        case .app(let selectedApp):
            let isActive = apps.contains { $0.bundleID == selectedApp.bundleID }

            if !isActive {
                AppLog.audio.info("event=autoSwitch.app.stop t=\(CACurrentMediaTime(), privacy: .public)")
                tapManager?.stop()
                tapManager = nil
                AudioDataBus.shared.resetPublisher.send()
            } else if tapManager == nil {
                if let match = apps.first(where: { $0.bundleID == selectedApp.bundleID }) {
                    AppLog.audio.info("event=autoSwitch.app.build app=\(match.bundleID ?? "nil", privacy: .public) t=\(CACurrentMediaTime(), privacy: .public)")
                    AppSettings.shared.audioSource = .app(match)
                    startTap(for: match)
                }
            }
        }
    }

    // MARK: - Tap Management

    private func startGlobalTap() {
        AppLog.audio.info("event=startGlobalTap t=\(CACurrentMediaTime(), privacy: .public)")
        setupTap { $0.startGlobal() }
    }

    private func startTap(for app: AudioApp) {
        AppLog.audio.info("event=startAppTap app=\(app.bundleID ?? "nil", privacy: .public) t=\(CACurrentMediaTime(), privacy: .public)")
        setupTap { $0.start(app: app) }
    }

    private func setupTap(_ activation: (AudioTapManager) -> Void) {
        let tap = AudioTapManager()
        tap.onAudioData = { [weak self] left, right in
            guard let self,
                  let bins = self.analyzer?.analyze(left: left, right: right) else { return }
            AudioDataBus.shared.lastSourceEmitTime = CACurrentMediaTime()
            AudioDataBus.shared.sourceEventCount &+= 1
            AudioDataBus.shared.spectrumPublisher.send(bins)
        }
        activation(tap)
        tapManager = tap
        AppLog.audio.info("event=setupTap.assigned t=\(CACurrentMediaTime(), privacy: .public)")
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        stopWatchdog()
        let timer = Timer(timeInterval: watchdogInterval, repeats: true) { [weak self] _ in
            self?.checkAudioStall()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func checkAudioStall() {
        guard tapManager != nil else { return }
        let last = AudioDataBus.shared.lastSourceEmitTime
        guard last > 0 else {
            AppLog.audio.debug("event=stallCheck.skip reason=noEmit t=\(CACurrentMediaTime(), privacy: .public)")
            return
        }

        let now = CACurrentMediaTime()
        let elapsed = now - last
        guard elapsed > stallThreshold else { return }
        let elapsedStr = String(format: "%.1f", elapsed)

        // Don't rebuild during dark wake (display asleep): no one is there to
        // approve the TCC prompt, so the rebuilt tap never delivers and we'd
        // re-prompt every tick forever. CGMainDisplayID covers clamshell +
        // external display (main = the lit external screen -> rebuild allowed).
        // Gate before the throttle so a dark-wake skip doesn't burn the window
        // -> first tick after real wake can rebuild immediately.
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else {
            AppLog.audio.debug("event=stallRebuild.skip reason=displayAsleep elapsed=\(elapsedStr, privacy: .public) t=\(CACurrentMediaTime(), privacy: .public)")
            return
        }

        // Throttle so a permanently-broken tap doesn't rebuild every tick
        guard now - lastWatchdogRebuild > minRebuildInterval else { return }
        lastWatchdogRebuild = now

        AppLog.audio.error("event=stallRebuild elapsed=\(elapsedStr, privacy: .public) t=\(CACurrentMediaTime(), privacy: .public)")
        rebuildCurrentTap()
    }

    private func rebuildCurrentTap() {
        AppLog.audio.info("event=watchdogRebuild t=\(CACurrentMediaTime(), privacy: .public)")
        switch AppSettings.shared.audioSource {
        case .global:
            switchSource(to: .global, reason: "watchdogRebuild")
        case .app(let selectedApp):
            // Refresh AudioApp to pick up current objectIDs (PID may have changed)
            let refreshed = AppSettings.shared.activeApps.first { $0.bundleID == selectedApp.bundleID } ?? selectedApp
            switchSource(to: .app(refreshed), reason: "watchdogRebuild")
        }
        // Reset baseline: the frozen pre-sleep value is 700s+ stale; without
        // this the next tick re-triggers before the new tap can deliver.
        AudioDataBus.shared.lastSourceEmitTime = CACurrentMediaTime()
    }
}
