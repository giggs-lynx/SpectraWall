//
//  AudioEngine.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/1.
//

import Combine
import QuartzCore

class AudioEngine {
    static let shared = AudioEngine()

    private var monitor: AudioProcessMonitor?
    private var tapManager: AudioTapManager?
    private var analyzer: AudioAnalyzer?
    private var settingsCancellable: AnyCancellable?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        analyzer = AudioAnalyzer(fftSize: 4096, binCount: 96)
        observeAudioSource()
        startMonitor()
    }

    func stop() {
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
}
