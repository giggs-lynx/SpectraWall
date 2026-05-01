//
//  BorderEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SpriteKit
import Combine

class BorderEffect: SKNode {

    // MARK: - Properties (Settings & State)

    private var settings: LayerSettings
    private var cancellables = Set<AnyCancellable>()

    private var borderSettings: BorderSettings {
        settings.effectSettings as? BorderSettings ?? .defaults
    }

    private struct StrokeState {
        var progress: Double = 0.0
        var nodes: [SKShapeNode] = []
    }

    private var strokes: [StrokeState] = []

    // Separate smoothed amplitudes — stroke 0 = left, stroke 1 = right
    private var smoothedLeft: Float = 0
    private var smoothedRight: Float = 0

    private var lastUpdateTime: TimeInterval = 0
    private var perimeterLength: CGFloat = 0

    // MARK: - Properties (Caching)

    private var sceneSize: CGSize = .zero
    private var segmentCache: [BorderSegment]?
    private var cachedSceneSize: CGSize = .zero
    private var cachedCornerRadius: Double = -1
    private let trailSegments = 20

    // MARK: - Initialization

    init(size: CGSize, settings: LayerSettings) {
        self.sceneSize = size
        self.settings = settings
        super.init()

        setupStrokes()
        subscribeToAudio()
        observeSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    }

    // MARK: - Setup & Visual Updates

    private func setupStrokes() {
        segmentCache = nil

        strokes.forEach { $0.nodes.forEach { $0.removeFromParent() } }
        strokes = []

        let count = borderSettings.strokeCount
        for i in 0..<count {
            var state = StrokeState()
            state.progress = count == 2 ? Double(i) * 0.5 : 0.0

            for _ in 0..<trailSegments {
                let node = SKShapeNode()
                node.lineWidth = 0
                node.lineCap = .round
                node.blendMode = .add
                addChild(node)
                state.nodes.append(node)
            }
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
        let bs = borderSettings
        let inset  = max(CGFloat(bs.baseWidth) / 2, 0)
        let width  = sceneSize.width  - inset * 2
        let height = sceneSize.height - inset * 2
        let radius = max(CGFloat(bs.cornerRadius) - inset, 0)

        let straightLength = 2 * (width - 2 * radius) + 2 * (height - 2 * radius)
        let cornerLength   = 2 * .pi * radius

        perimeterLength = straightLength + cornerLength
    }

    // MARK: - Main Update Loop

    func update(_ currentTime: TimeInterval) {
        guard lastUpdateTime > 0 else {
            lastUpdateTime = currentTime
            return
        }

        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        let bs = borderSettings
        let deltaProgress = bs.speed * deltaTime * (bs.clockwise ? 1 : -1)

        for i in 0..<strokes.count {
            var progress = (strokes[i].progress + deltaProgress).truncatingRemainder(dividingBy: 1.0)
            if progress < 0 { progress += 1.0 }
            strokes[i].progress = progress
            renderStroke(index: i)
        }
    }

    // MARK: - Rendering Logic

    private func renderStroke(index: Int) {
        let stroke = strokes[index]
        let bs = borderSettings
        let clockwise = bs.clockwise

        let colorStart = index == 0 ? bs.stroke1ColorStart : bs.stroke2ColorStart
        let colorEnd   = index == 0 ? bs.stroke1ColorEnd   : bs.stroke2ColorEnd

        // stroke 0 → left channel, stroke 1 → right channel
        // When only 1 stroke, fall back to combined amplitude
        let amplitude: Float
        if strokes.count == 1 {
            amplitude = (smoothedLeft + smoothedRight) / 2
        } else {
            amplitude = index == 0 ? smoothedLeft : smoothedRight
        }

        let pulseWidth = CGFloat(amplitude) * 8.0
        let baseWidth  = CGFloat(bs.baseWidth) + pulseWidth
        let tailLength = bs.tailLength

        for j in 0..<trailSegments {
            let node = stroke.nodes[j]

            let tProgress: Double = clockwise
                ? Double(j) / Double(trailSegments - 1)
                : 1.0 - Double(j) / Double(trailSegments - 1)

            let offset = clockwise
                ? -(1.0 - tProgress) * tailLength
                :  (1.0 - tProgress) * tailLength

            let segProgress    = (stroke.progress + offset).truncatingRemainder(dividingBy: 1.0)
            let adjustedProgress = segProgress < 0 ? segProgress + 1.0 : segProgress

            let segLength = perimeterLength * CGFloat(tailLength) / CGFloat(trailSegments)
            node.path = borderPath(from: adjustedProgress, length: segLength, clockwise: clockwise)

            node.strokeColor = interpolateColor(
                from: colorEnd.nsColor,
                to: colorStart.nsColor,
                progress: CGFloat(tProgress)
            )
            node.lineWidth = baseWidth * CGFloat(tProgress)
            node.alpha     = CGFloat(tProgress)
        }
    }

    // MARK: - Path & Geometry

    private func borderPath(from progress: Double, length: CGFloat, clockwise: Bool) -> CGPath {
        let path = CGMutablePath()
        var drawn: CGFloat = 0
        var current = CGFloat(progress) * perimeterLength
        var isStarted = false
        let segments = borderSegments()

        while drawn < length {
            let wrapped = current.truncatingRemainder(dividingBy: perimeterLength)
            let (segIndex, localDist) = segmentAt(distance: wrapped, segments: segments)
            let seg = segments[segIndex]
            let remaining = seg.length - localDist
            let toDraw    = min(remaining, length - drawn)
            let startT    = localDist / seg.length
            let endT      = (localDist + toDraw) / seg.length

            if !isStarted {
                path.move(to: seg.point(at: startT))
                isStarted = true
            }

            if seg.isArc {
                let startAngle = seg.startAngle + (seg.endAngle - seg.startAngle) * startT
                let endAngle   = seg.startAngle + (seg.endAngle - seg.startAngle) * endT
                path.addArc(
                    center: seg.center,
                    radius: seg.radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
            } else {
                path.addLine(to: seg.point(at: endT))
            }

            drawn   += toDraw
            current += toDraw
        }

        return path
    }

    private func borderSegments() -> [BorderSegment] {
        let bs = borderSettings
        let inset = max(CGFloat(bs.baseWidth) / 2, 0)

        if let cache = segmentCache,
           cachedSceneSize == sceneSize,
           cachedCornerRadius == bs.cornerRadius {
            return cache
        }

        let width  = sceneSize.width  - inset * 2
        let height = sceneSize.height - inset * 2
        let radius = max(CGFloat(bs.cornerRadius) - inset, 0)
        let pi = CGFloat.pi

        let segs: [BorderSegment] = [
            // Bottom
            BorderSegment(length: width - 2 * radius, isArc: false,
                startPoint: CGPoint(x: inset + radius,         y: inset),
                endPoint:   CGPoint(x: inset + width - radius, y: inset)),
            // Bottom-Right
            BorderSegment(length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + width - radius, y: inset + radius),
                radius: radius, startAngle: -pi / 2, endAngle: 0),
            // Right
            BorderSegment(length: height - 2 * radius, isArc: false,
                startPoint: CGPoint(x: inset + width, y: inset + radius),
                endPoint:   CGPoint(x: inset + width, y: inset + height - radius)),
            // Top-Right
            BorderSegment(length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + width - radius, y: inset + height - radius),
                radius: radius, startAngle: 0, endAngle: pi / 2),
            // Top
            BorderSegment(length: width - 2 * radius, isArc: false,
                startPoint: CGPoint(x: inset + width - radius, y: inset + height),
                endPoint:   CGPoint(x: inset + radius,         y: inset + height)),
            // Top-Left
            BorderSegment(length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + radius, y: inset + height - radius),
                radius: radius, startAngle: pi / 2, endAngle: pi),
            // Left
            BorderSegment(length: height - 2 * radius, isArc: false,
                startPoint: CGPoint(x: inset, y: inset + height - radius),
                endPoint:   CGPoint(x: inset, y: inset + radius)),
            // Bottom-Left
            BorderSegment(length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + radius, y: inset + radius),
                radius: radius, startAngle: pi, endAngle: 3 * pi / 2),
        ]

        segmentCache       = segs
        cachedSceneSize    = sceneSize
        cachedCornerRadius = bs.cornerRadius
        return segs
    }

    private func segmentAt(distance: CGFloat, segments: [BorderSegment]) -> (Int, CGFloat) {
        var accumulated: CGFloat = 0
        for (i, seg) in segments.enumerated() {
            if accumulated + seg.length > distance {
                return (i, distance - accumulated)
            }
            accumulated += seg.length
        }
        return (segments.count - 1, distance - accumulated)
    }

    // MARK: - Helper Structs & Methods

    private struct BorderSegment {
        var length: CGFloat
        var isArc: Bool
        var startPoint: CGPoint = .zero
        var endPoint:   CGPoint = .zero
        var center:     CGPoint = .zero
        var radius:     CGFloat = 0
        var startAngle: CGFloat = 0
        var endAngle:   CGFloat = 0

        func point(at progress: CGFloat) -> CGPoint {
            if isArc {
                let angle = startAngle + (endAngle - startAngle) * progress
                return CGPoint(x: center.x + radius * cos(angle),
                               y: center.y + radius * sin(angle))
            } else {
                return CGPoint(
                    x: startPoint.x + (endPoint.x - startPoint.x) * progress,
                    y: startPoint.y + (endPoint.y - startPoint.y) * progress
                )
            }
        }
    }

    private func interpolateColor(from: NSColor, to: NSColor, progress: CGFloat) -> NSColor {
        NSColor(
            red:   from.redComponent   + (to.redComponent   - from.redComponent)   * progress,
            green: from.greenComponent + (to.greenComponent - from.greenComponent) * progress,
            blue:  from.blueComponent  + (to.blueComponent  - from.blueComponent)  * progress,
            alpha: 1.0
        )
    }
}
