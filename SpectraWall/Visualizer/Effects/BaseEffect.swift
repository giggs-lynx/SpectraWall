//
//  BaseEffect.swift
//  SpectraWall
//
//  Common scaffolding for visual effects: renderer attachment, visibility &
//  opacity bookkeeping, the audio Combine plumbing, the per-frame guard and
//  lifecycle log. Subclasses override the small set of hooks (`onTick`,
//  `onAudio`, `onReset`, `removeFromRenderer`) plus declare their effect-type
//  label for logs.
//
//  Marked `nonisolated` because tick/audio sinks run on the renderer's serial
//  queue, not on MainActor — without this the default actor isolation
//  (configured to MainActor module-wide) would force everything through main.
//

import AppKit
import Combine
import OSLog

class BaseEffect: Effect {

    // MARK: - Effect protocol

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    let layer: LayerSettings
    var isVisible: Bool
    var opacity: Float

    // MARK: - State

    let sceneSize: CGSize
    weak var renderer: EffectRenderer?
    var cancellables = Set<AnyCancellable>()

    private(set) var isStopped = false
    private var wasVisible = true

    // MARK: - Lifecycle

    init(size: CGSize, layer: LayerSettings, screen: NSScreen) {
        self.sceneSize = size
        self.layer = layer
        self.opacity = Float(layer.opacity)
        self.isVisible = layer.isVisible

        AppLog.effect.info(
            "start type=\(Self.effectTypeName, privacy: .public) layer=\(self.layer.id, privacy: .public)"
        )

        attachToRenderer(for: screen)
        subscribeToAudio()
        observeLayerVisibility()
    }

    /// Effect-type label printed in lifecycle logs. Subclass overrides.
    class var effectTypeName: String { String(describing: self) }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        renderer?.removeFrameClient(id: id)
        removeFromRenderer()
        AppLog.effect.info(
            "stop type=\(Self.effectTypeName, privacy: .public) layer=\(self.layer.id, privacy: .public)"
        )
    }

    deinit { stop() }

    // MARK: - Subclass hooks

    /// Called every frame after the visibility/stopped guard passes.
    func onTick(_ timestamp: TimeInterval) {}

    /// Called when fresh audio bins arrive on the renderer's serial queue.
    func onAudio(_ bins: StereoBins) {}

    /// Called when AudioDataBus.resetPublisher fires (audio source switched).
    func onReset() {}

    /// Drop our submission from the renderer. Default implementation issues
    /// the unified `remove(id:)`; subclasses can override if they need to
    /// clear additional internal state at removal time.
    func removeFromRenderer() {
        renderer?.remove(id: id)
    }

    /// Called on every layer.objectWillChange after the base class has
    /// refreshed `opacity` and `isVisible`. Default does nothing; effects
    /// with structural settings (BorderEffect rebuilds geometry on
    /// strokeCount / cornerRadius / baseWidth changes) override this.
    func onLayerSettingsChanged() {}

    // MARK: - Frame entry

    /// Per-frame entry point from the renderer's tick client registry.
    /// Handles the isStopped / isVisible / wasVisible transition guard so
    /// every subclass gets a clean onTick(_:) when it should actually draw.
    private func tick(timestamp: TimeInterval) {
        guard !isStopped else { return }
        guard isVisible else {
            if wasVisible {
                removeFromRenderer()
                wasVisible = false
            }
            return
        }
        wasVisible = true
        onTick(timestamp)
    }

    // MARK: - Wiring

    private func attachToRenderer(for screen: NSScreen) {
        renderer = EffectRendererRegistry.shared.renderer(for: screen)
        let myID = id
        renderer?.addFrameClient(id: myID) { [weak self] t in
            self?.tick(timestamp: t)
        }
    }

    private func subscribeToAudio() {
        // Receive on the renderer's private queue so audio-driven state and
        // tick(_:) reads happen on the same serial queue — no locks, no
        // main-thread dependency for the audio path.
        let queue: DispatchQueue = renderer?.renderQueue ?? .main
        AudioDataBus.shared.spectrumPublisher
            .receive(on: queue)
            .sink { [weak self] bins in self?.onAudio(bins) }
            .store(in: &cancellables)
        AudioDataBus.shared.resetPublisher
            .receive(on: queue)
            .sink { [weak self] _ in self?.onReset() }
            .store(in: &cancellables)
    }

    private func observeLayerVisibility() {
        layer.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.opacity = Float(self.layer.opacity)
                self.isVisible = self.layer.isVisible
                self.onLayerSettingsChanged()
            }
            .store(in: &cancellables)
    }
}
