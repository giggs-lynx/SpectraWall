//
//  BorderEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SpriteKit
import Combine

class BorderEffect: SKNode, UpdatableEffectNode {

    // MARK: - Properties (Settings & State)

    private var settings: LayerSettings
    private var cancellables = Set<AnyCancellable>()

    var borderSettings: BorderSettings {
        settings.effectSettings as? BorderSettings ?? .defaults
    }

    struct StrokeState {
        var progress: Double = 0.0
    }

    var strokes: [StrokeState] = []

    var smoothedLeft: Float = 0
    var smoothedRight: Float = 0
    var lastAmplitudeLeft: Float = 0
    var lastAmplitudeRight: Float = 0

    private var lastUpdateTime: TimeInterval = 0
    var perimeterLength: CGFloat = 0

    // MARK: - Scale Pulse Echo

    struct ScaleGhost {
        var lifetime: CGFloat
        var delay: CGFloat
        var progressOffset: Double
        var strokeIndex: Int
        var amplitude: Float
    }

    var scaleGhosts: [ScaleGhost] = []

    let echoThreshold: Float     = 0.08
    let echoDecaySpeed: CGFloat  = 1.5
    let echoMaxScale: CGFloat    = 5.0
    let echoStartAlpha: CGFloat  = 0.25
    let echoLayerCount: Int      = 3
    let echoLayerDelay: CGFloat  = 3.0
    let maxScaleGhosts: Int      = 20

    // MARK: - Properties (Caching)

    var sceneSize: CGSize = .zero
    var segmentCache: [BorderSegment]?
    var cachedSceneSize: CGSize = .zero
    var cachedCornerRadius: Double = -1
    let trailSegments = 20

    weak var trailRenderer: BorderTrailRenderer?
    var rendererID: ObjectIdentifier?

    // MARK: - Initialization

    init(size: CGSize, settings: LayerSettings, screen: NSScreen) {
        self.sceneSize = size
        self.settings = settings
        super.init()

        setupStrokes()
        subscribeToAudio()
        observeSettings()
        findRenderer(for: screen)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func findRenderer(for screen: NSScreen) {
        trailRenderer = BorderTrailRendererRegistry.shared.renderer(for: screen)
        rendererID = ObjectIdentifier(self)
    }

    deinit {
        if let id = rendererID {
            trailRenderer?.removeTrail(id: id)
        }
    }

    // MARK: - Lifecycle & Observation

    private func observeSettings() {
        var lastCount  = borderSettings.strokeCount
        var lastRadius = borderSettings.cornerRadius
        var lastWidth  = borderSettings.baseWidth

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let bs = self.borderSettings
                if bs.strokeCount != lastCount ||
                   bs.cornerRadius != lastRadius ||
                   bs.baseWidth    != lastWidth {
                    lastCount  = bs.strokeCount
                    lastRadius = bs.cornerRadius
                    lastWidth  = bs.baseWidth
                    self.setupStrokes()
                } else {
                    self.updateVisuals()
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToAudio() {
        AudioDataBus.shared.spectrumPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bins in
                self?.updateAmplitude(bins: bins)
            }
            .store(in: &cancellables)

        AudioDataBus.shared.resetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reset()
            }
            .store(in: &cancellables)
    }

    // MARK: - Audio

    private func updateAmplitude(bins: StereoBins) {
        let bs = borderSettings
        let leftAmp  = bins.leftAmplitude()
        let rightAmp = bins.rightAmplitude()

        let leftCoeff  = leftAmp  > smoothedLeft  ? Float(bs.pulseAttack) : Float(bs.pulseRelease)
        let rightCoeff = rightAmp > smoothedRight ? Float(bs.pulseAttack) : Float(bs.pulseRelease)

        smoothedLeft  = smoothedLeft  * (1 - leftCoeff)  + leftAmp  * leftCoeff
        smoothedRight = smoothedRight * (1 - rightCoeff) + rightAmp * rightCoeff

        detectAndSpawnEcho()

        lastAmplitudeLeft  = smoothedLeft
        lastAmplitudeRight = smoothedRight
    }

    private var lastEchoTime: TimeInterval = 0
    private let minEchoInterval: TimeInterval = 0.12

    private func detectAndSpawnEcho() {
        guard scaleGhosts.count < maxScaleGhosts else { return }

        let now = lastUpdateTime
        guard now - lastEchoTime > minEchoInterval else { return }

        let bs = borderSettings
        let sensitivity: Float = 1.1

        if strokes.count == 1 {
            let combined = (smoothedLeft + smoothedRight) / 2
            let lastCombined = (lastAmplitudeLeft + lastAmplitudeRight) / 2
            if combined > Float(bs.pulseThreshold) && combined > lastCombined * sensitivity {
                spawnScalePulse(strokeIndex: 0, amplitude: combined)
                lastEchoTime = now
            }
        } else {
            if smoothedLeft > Float(bs.pulseThreshold) && smoothedLeft > lastAmplitudeLeft * sensitivity {
                spawnScalePulse(strokeIndex: 0, amplitude: smoothedLeft)
                lastEchoTime = now
            }
            if smoothedRight > Float(bs.pulseThreshold) && smoothedRight > lastAmplitudeRight * sensitivity {
                spawnScalePulse(strokeIndex: 1, amplitude: smoothedRight)
                lastEchoTime = now
            }
        }
    }

    // MARK: - Spawn Scale Pulse

    private func spawnScalePulse(strokeIndex: Int, amplitude: Float) {
        for layerIndex in 0..<echoLayerCount {
            scaleGhosts.append(ScaleGhost(
                lifetime: -0.05,
                delay: CGFloat(layerIndex) * echoLayerDelay,
                progressOffset: 0.0,
                strokeIndex: strokeIndex,
                amplitude: amplitude
            ))
        }
    }

    // MARK: - Scale Ghost Update

    private func updateScaleGhosts(deltaTime: TimeInterval) -> [TrailVertex] {
        let dt = CGFloat(deltaTime)
        var ghostVertices: [TrailVertex] = []

        for index in (0..<scaleGhosts.count).reversed() {
            if scaleGhosts[index].delay > 0 {
                scaleGhosts[index].delay -= dt
                continue
            }

            scaleGhosts[index].lifetime += dt * echoDecaySpeed
            let lifetime = scaleGhosts[index].lifetime

            if lifetime >= 1.0 {
                scaleGhosts.remove(at: index)
                continue
            }

            guard lifetime >= 0 else { continue }

            let easedT = 1.0 - pow(max(0, 1.0 - lifetime), 4)
            let scale  = 1.0 + easedT * (echoMaxScale - 1.0)
            let alpha  = Float(echoStartAlpha * max(0, 1.0 - pow(lifetime, 1.2)))

            let ghost = scaleGhosts[index]
            let data = buildGhostTrailData(
                strokeIndex: ghost.strokeIndex,
                progressOffset: ghost.progressOffset,
                amplitude: ghost.amplitude,
                scale: CGFloat(scale),
                alpha: alpha
            )

            if !ghostVertices.isEmpty,
               let last = ghostVertices.last,
               let first = data.vertices.first {
                ghostVertices.append(last)
                ghostVertices.append(last)
                ghostVertices.append(first)
            }
            ghostVertices.append(contentsOf: data.vertices)
        }

        return ghostVertices
    }

    // MARK: - Setup & Visual Updates

    private func setupStrokes() {
        segmentCache = nil
        scaleGhosts = []
        strokes = []

        let count = borderSettings.strokeCount
        for strokeIndex in 0..<count {
            var state = StrokeState()
            state.progress = count == 2 ? Double(strokeIndex) * 0.5 : 0.0
            strokes.append(state)
        }

        updatePerimeterLength()
        updateVisuals()
    }

    private func updateVisuals() {
        alpha = CGFloat(settings.opacity)
        updatePerimeterLength()
    }

    private func updatePerimeterLength() {
        let bs     = borderSettings
        let inset  = max(CGFloat(bs.baseWidth) / 2, 0)
        let width  = max(0, sceneSize.width  - inset * 2)
        let height = max(0, sceneSize.height - inset * 2)
        let radius = max(CGFloat(bs.cornerRadius) - inset, 0)

        perimeterLength = max(0,
            2 * max(0, width  - 2 * radius) +
            2 * max(0, height - 2 * radius) +
            2 * .pi * radius
        )
    }

    // MARK: - Main Update Loop

    func update(_ currentTime: TimeInterval) {
        guard lastUpdateTime > 0 else {
            lastUpdateTime = currentTime
            return
        }

        let deltaTime     = currentTime - lastUpdateTime
        lastUpdateTime    = currentTime

        let bs            = borderSettings
        let deltaProgress = bs.speed * deltaTime * (bs.clockwise ? 1 : -1)

        for strokeIndex in 0..<strokes.count {
            var progress = (strokes[strokeIndex].progress + deltaProgress)
                .truncatingRemainder(dividingBy: 1.0)
            if progress < 0 { progress += 1.0 }
            strokes[strokeIndex].progress = progress
        }

        guard let renderer = trailRenderer, let id = rendererID else { return }

        var allVertices: [TrailVertex] = []
        allVertices.reserveCapacity(300 * strokes.count + 300 * scaleGhosts.count)

        for strokeIndex in 0..<strokes.count {
            let data = buildTrailData(strokeIndex: strokeIndex)
            if !allVertices.isEmpty,
               let last = allVertices.last,
               let first = data.vertices.first {
                allVertices.append(last)
                allVertices.append(last)
                allVertices.append(first)
            }
            allVertices.append(contentsOf: data.vertices)
        }

        let ghostVerts = updateScaleGhosts(deltaTime: deltaTime)
        if !ghostVerts.isEmpty {
            if let last = allVertices.last, let first = ghostVerts.first {
                allVertices.append(last)
                allVertices.append(last)
                allVertices.append(first)
            }
            allVertices.append(contentsOf: ghostVerts)
        }

        renderer.updateTrail(id: id, data: TrailData(vertices: allVertices))
    }

    // MARK: - Reset

    func reset() {
        smoothedLeft       = 0
        smoothedRight      = 0
        lastAmplitudeLeft  = 0
        lastAmplitudeRight = 0
        scaleGhosts        = []
    }
}
