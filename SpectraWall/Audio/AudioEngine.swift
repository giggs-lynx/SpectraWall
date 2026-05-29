//
//  AudioEngine.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/1.
//

import Combine
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

    private func switchSource(to source: AudioSource) {
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
        switch AppSettings.shared.audioSource {
        case .global:
            if tapManager == nil { startGlobalTap() }
        case .app(let selectedApp):
            let isActive = apps.contains { $0.bundleID == selectedApp.bundleID }

            if !isActive {
                tapManager?.stop()
                tapManager = nil
                AudioDataBus.shared.resetPublisher.send()
            } else if tapManager == nil {
                if let match = apps.first(where: { $0.bundleID == selectedApp.bundleID }) {
                    AppSettings.shared.audioSource = .app(match)
                    startTap(for: match)
                }
            }
        }
    }

    // MARK: - Tap Management

    private func startGlobalTap() {
        setupTap { $0.startGlobal() }
    }

    private func startTap(for app: AudioApp) {
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
        guard last > 0 else { return }

        let now = CACurrentMediaTime()
        let elapsed = now - last
        guard elapsed > stallThreshold else { return }

        // Throttle so a permanently-broken tap doesn't rebuild every tick
        guard now - lastWatchdogRebuild > minRebuildInterval else { return }
        lastWatchdogRebuild = now

        let elapsedStr = String(format: "%.1f", elapsed)
        AppLog.audio.error("Audio tap stalled (\(elapsedStr)s without IOProc callback), rebuilding")
        rebuildCurrentTap()
    }

    private func rebuildCurrentTap() {
        switch AppSettings.shared.audioSource {
        case .global:
            switchSource(to: .global)
        case .app(let selectedApp):
            // Refresh AudioApp to pick up current objectIDs (PID may have changed)
            let refreshed = AppSettings.shared.activeApps.first { $0.bundleID == selectedApp.bundleID } ?? selectedApp
            switchSource(to: .app(refreshed))
        }
    }
}
