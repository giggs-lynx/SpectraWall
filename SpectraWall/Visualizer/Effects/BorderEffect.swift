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

    private var borderSettings: BorderSettings {
        settings.effectSettings as? BorderSettings ?? .defaults
    }

    private struct StrokeState {
        var progress: Double = 0.0
        var nodes: [SKShapeNode] = []
    }

    private var strokes: [StrokeState] = []

    private var smoothedLeft: Float = 0
    private var smoothedRight: Float = 0
    private var lastAmplitudeLeft: Float = 0
    private var lastAmplitudeRight: Float = 0

    private var lastUpdateTime: TimeInterval = 0
    private var perimeterLength: CGFloat = 0

    // MARK: - Scale Pulse Echo
    //
    // On beat hit, snapshot the stroke tail as a path relative to its bounding center.
    // The ghost node is positioned at that center, so xScale/yScale expand outward
    // from the stroke's own center — exactly like a "scaling pulse" shader effect.

    private struct ScaleGhost {
        var lifetime: CGFloat       // 0 → 1, removed at 1
        var delay: CGFloat          // seconds before activating
        var peakWidth: CGFloat
        var colorStart: NSColor
        var colorEnd: NSColor
        let node: SKShapeNode       // positioned at bounding center, path is relative
    }

    private var scaleGhosts: [ScaleGhost] = []

    // Tune these to taste
    private let echoThreshold: Float    = 0.08   // amplitude rising edge to trigger
    private let echoDecaySpeed: CGFloat = 1.5    // lower = slower fade
    private let echoMaxScale: CGFloat   = 3.0    // ghost scales from 1x to this
    private let echoStartAlpha: CGFloat = 0.7    // initial alpha of ghost
    private let echoLayerCount: Int     = 3      // ghosts per beat
    private let echoLayerDelay: CGFloat = 0.04   // stagger between layers (seconds)
    private let maxScaleGhosts: Int     = 20

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

    // 在類別屬性區（Properties）增加冷卻時間記錄
    private var lastEchoTime: TimeInterval = 0
    private let minEchoInterval: TimeInterval = 0.12 // 約 8Hz，防止太碎

    private func detectAndSpawnEcho() {
        guard scaleGhosts.count < maxScaleGhosts else { return }
        
        // 獲取目前時間（從 update 循環傳入，或直接取類別內的 lastUpdateTime）
        let now = lastUpdateTime
        guard now - lastEchoTime > minEchoInterval else { return }

        let bs = borderSettings
        // 靈敏度係數：目前振幅必須比上一幀高出 10% 且超過基本門檻
        let sensitivity: Float = 1.1

        if strokes.count == 1 {
            let combined = (smoothedLeft + smoothedRight) / 2
            let lastCombined = (lastAmplitudeLeft + lastAmplitudeRight) / 2
            
            // 觸發條件：
            // 1. 超過基本門檻 (echoThreshold)
            // 2. 且 這一幀比上一幀強 10% (具備足夠的 Attack 斜率)
            if combined > Float(bs.pulseThreshold) && combined > lastCombined * sensitivity {
                spawnScalePulse(strokeIndex: 0, amplitude: combined)
                lastEchoTime = now
            }
        } else {
            // 左聲道判斷
            if smoothedLeft > Float(bs.pulseThreshold) && smoothedLeft > lastAmplitudeLeft * sensitivity {
                spawnScalePulse(strokeIndex: 0, amplitude: smoothedLeft)
                lastEchoTime = now
            }
            // 右聲道判斷 (若左聲道剛觸發，這邊會被冷卻機制過濾，除非你想要左右獨立計時)
            if smoothedRight > Float(bs.pulseThreshold) && smoothedRight > lastAmplitudeRight * sensitivity {
                spawnScalePulse(strokeIndex: 1, amplitude: smoothedRight)
                lastEchoTime = now
            }
        }
    }

    // MARK: - Spawn Scale Pulse

    private func spawnScalePulse(strokeIndex: Int, amplitude: Float) {
        guard strokeIndex < strokes.count else { return }
        let bs = borderSettings

        let colorStart = strokeIndex == 0 ? bs.stroke1ColorStart.nsColor : bs.stroke2ColorStart.nsColor
        let colorEnd   = strokeIndex == 0 ? bs.stroke1ColorEnd.nsColor   : bs.stroke2ColorEnd.nsColor

        // Collect the world-space points of the full stroke tail
        let tailPoints = collectTailPoints(
            strokeIndex: strokeIndex,
            tailLength: bs.tailLength,
            clockwise: bs.clockwise
        )
        guard tailPoints.count >= 2 else { return }

        // Compute bounding center of the tail — this becomes the scale anchor
        let center = boundingCenter(of: tailPoints)

        // Build path relative to center so scale expands from the stroke's own center
        let relativePath = makeRelativePath(points: tailPoints, center: center)

        for i in 0..<echoLayerCount {
            let node = SKShapeNode()
            node.path        = relativePath
            node.strokeColor = interpolateColor(from: colorEnd, to: colorStart, progress: 0.8)
            node.lineWidth   = CGFloat(bs.baseWidth) + CGFloat(amplitude) * 10
            node.lineCap     = .round
            node.lineJoin    = .round
            node.blendMode   = .add
            node.fillColor   = .clear
            node.position    = center           // anchor at bounding center
            node.xScale      = 1.0
            node.yScale      = 1.0
            node.alpha       = 0               // start invisible, activated after delay
            node.zPosition   = CGFloat(10 + i)
            addChild(node)

            let layerFactor = 1.0 - CGFloat(i) * 0.2
            let ghost = ScaleGhost(
                lifetime: 0,
                delay: CGFloat(i) * echoLayerDelay,
                peakWidth: (CGFloat(bs.baseWidth) + CGFloat(amplitude) * 10) * layerFactor,
                colorStart: colorStart,
                colorEnd: colorEnd,
                node: node
            )
            scaleGhosts.append(ghost)
        }
    }

    // MARK: - Tail Point Collection

    /// Collect evenly-spaced world-space points along the full stroke tail
    private func collectTailPoints(
        strokeIndex: Int,
        tailLength: Double,
        clockwise: Bool
    ) -> [CGPoint] {
        let segments = borderSegments()
        guard perimeterLength > 0, !segments.isEmpty else { return [] }

        let resolution  = 60
        let tailDist    = perimeterLength * CGFloat(tailLength)
        let headDist    = CGFloat(strokes[strokeIndex].progress) * perimeterLength

        // Start of tail (behind the head)
        let startDist: CGFloat
        if clockwise {
            startDist = ((headDist - tailDist)
                .truncatingRemainder(dividingBy: perimeterLength) + perimeterLength)
                .truncatingRemainder(dividingBy: perimeterLength)
        } else {
            startDist = headDist
        }

        var points: [CGPoint] = []
        points.reserveCapacity(resolution)

        for k in 0..<resolution {
            let t = CGFloat(k) / CGFloat(resolution - 1)
            let dist: CGFloat
            if clockwise {
                dist = (startDist + t * tailDist)
                    .truncatingRemainder(dividingBy: perimeterLength)
            } else {
                dist = ((startDist - t * tailDist)
                    .truncatingRemainder(dividingBy: perimeterLength) + perimeterLength)
                    .truncatingRemainder(dividingBy: perimeterLength)
            }

            let (segIdx, localDist) = segmentAt(distance: dist, segments: segments)
            let seg   = segments[segIdx]
            let localT = seg.length > 0 ? localDist / seg.length : 0
            points.append(seg.point(at: localT))
        }

        return points
    }

    /// Bounding box center of a set of points
    private func boundingCenter(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let minX = points.map { $0.x }.min()!
        let maxX = points.map { $0.x }.max()!
        let minY = points.map { $0.y }.min()!
        let maxY = points.map { $0.y }.max()!
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    /// Build a CGPath from points, translated so center becomes origin (0,0)
    private func makeRelativePath(points: [CGPoint], center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x - center.x, y: first.y - center.y))
        for p in points.dropFirst() {
            path.addLine(to: CGPoint(x: p.x - center.x, y: p.y - center.y))
        }
        return path
    }

    // MARK: - Scale Ghost Update

    private func updateScaleGhosts(deltaTime: TimeInterval) {
        let dt = CGFloat(deltaTime)

        for i in (0..<scaleGhosts.count).reversed() {
            // Wait out the stagger delay
            if scaleGhosts[i].delay > 0 {
                scaleGhosts[i].delay -= dt
                continue
            }

            scaleGhosts[i].lifetime += dt * echoDecaySpeed
            let t = scaleGhosts[i].lifetime  // 0 → 1

            // pow(x, 4): scale explodes outward fast then decelerates sharply
            // — creates the "tension burst / impact" feel
            let easedT = 1.0 - pow(max(0, 1.0 - t), 4)
            let scale  = 1.0 + easedT * (echoMaxScale - 1.0)

            // Alpha fades from echoStartAlpha → 0
            let alpha = echoStartAlpha * max(0, 1.0 - pow(t, 1.2))

            let node = scaleGhosts[i].node
            node.xScale = scale
            node.yScale = scale
            node.alpha  = alpha

            if scaleGhosts[i].lifetime >= 1.0 {
                node.removeFromParent()
                scaleGhosts.remove(at: i)
            }
        }
    }

    // MARK: - Setup & Visual Updates

    private func setupStrokes() {
        segmentCache = nil

        scaleGhosts.forEach { $0.node.removeFromParent() }
        scaleGhosts = []

        strokes.forEach { $0.nodes.forEach { $0.removeFromParent() } }
        strokes = []

        let count = borderSettings.strokeCount
        for i in 0..<count {
            var state = StrokeState()
            state.progress = count == 2 ? Double(i) * 0.5 : 0.0

            for _ in 0..<trailSegments {
                let node = SKShapeNode()
                node.lineWidth = 0
                node.lineCap   = .round
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

        for i in 0..<strokes.count {
            var p = (strokes[i].progress + deltaProgress).truncatingRemainder(dividingBy: 1.0)
            if p < 0 { p += 1.0 }
            strokes[i].progress = p
            renderStroke(index: i)
        }

        updateScaleGhosts(deltaTime: deltaTime)
    }

    // MARK: - Rendering Logic

    private func renderStroke(index: Int) {
        let stroke    = strokes[index]
        let bs        = borderSettings
        let clockwise = bs.clockwise

        let colorStart = index == 0 ? bs.stroke1ColorStart : bs.stroke2ColorStart
        let colorEnd   = index == 0 ? bs.stroke1ColorEnd   : bs.stroke2ColorEnd

        let amplitude: Float = strokes.count == 1
            ? (smoothedLeft + smoothedRight) / 2
            : (index == 0 ? smoothedLeft : smoothedRight)

        let baseWidth  = CGFloat(bs.baseWidth)
        let tailLength = bs.tailLength

        for j in 0..<trailSegments {
            let node = stroke.nodes[j]

            let tProgress: Double = clockwise
                ? Double(j) / Double(trailSegments - 1)
                : 1.0 - Double(j) / Double(trailSegments - 1)

            let offset = clockwise
                ? -(1.0 - tProgress) * tailLength
                :  (1.0 - tProgress) * tailLength

            let segProgress      = (stroke.progress + offset).truncatingRemainder(dividingBy: 1.0)
            let adjustedProgress = segProgress < 0 ? segProgress + 1.0 : segProgress

            let segLength = perimeterLength * CGFloat(tailLength) / CGFloat(trailSegments)
            node.path = borderPath(from: adjustedProgress, length: segLength, clockwise: clockwise)

            node.strokeColor = interpolateColor(
                from: colorEnd.nsColor,
                to: colorStart.nsColor,
                progress: CGFloat(tProgress)
            )
            node.lineWidth = (baseWidth + CGFloat(amplitude) * 3.0) * CGFloat(tProgress)
            node.alpha     = CGFloat(tProgress)
        }
    }

    // MARK: - Path & Geometry

    private func borderPath(from progress: Double, length: CGFloat, clockwise: Bool) -> CGPath {
        let path     = CGMutablePath()
        let segments = borderSegments()
        guard perimeterLength > 0, length > 0 else { return path }

        // 把整條 trail 取樣成足夠多的點，直接連線
        let steps = 120
        var isStarted = false

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let distAlongTrail = t * length

            let rawDist = CGFloat(progress) * perimeterLength + (clockwise ? distAlongTrail : -distAlongTrail)
            let wrapped = ((rawDist.truncatingRemainder(dividingBy: perimeterLength)) + perimeterLength)
                .truncatingRemainder(dividingBy: perimeterLength)

            let (segIdx, localDist) = segmentAt(distance: wrapped, segments: segments)
            let seg = segments[segIdx]
            let localT = seg.length > 0 ? min(localDist / seg.length, 1.0) : 0
            let point = seg.point(at: localT)

            if !isStarted {
                path.move(to: point)
                isStarted = true
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func borderSegments() -> [BorderSegment] {
        let bs    = borderSettings
        let inset = max(CGFloat(bs.baseWidth) / 2, 0)

        if let cache = segmentCache,
           cachedSceneSize == sceneSize,
           cachedCornerRadius == bs.cornerRadius {
            return cache
        }

        let width  = max(0, sceneSize.width  - inset * 2)
        let height = max(0, sceneSize.height - inset * 2)
        let radius = max(CGFloat(bs.cornerRadius) - inset, 0)
        let pi     = CGFloat.pi

        let segs: [BorderSegment] = [
            BorderSegment(
                length: max(0, width - 2 * radius), isArc: false,
                startPoint: CGPoint(x: inset + radius,         y: inset),
                endPoint:   CGPoint(x: inset + width - radius, y: inset)),
            BorderSegment(
                length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + width - radius, y: inset + radius),
                radius: radius, startAngle: -pi / 2, endAngle: 0),
            BorderSegment(
                length: max(0, height - 2 * radius), isArc: false,
                startPoint: CGPoint(x: inset + width, y: inset + radius),
                endPoint:   CGPoint(x: inset + width, y: inset + height - radius)),
            BorderSegment(
                length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + width - radius, y: inset + height - radius),
                radius: radius, startAngle: 0, endAngle: pi / 2),
            BorderSegment(
                length: max(0, width - 2 * radius), isArc: false,
                startPoint: CGPoint(x: inset + width - radius, y: inset + height),
                endPoint:   CGPoint(x: inset + radius,         y: inset + height)),
            BorderSegment(
                length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + radius, y: inset + height - radius),
                radius: radius, startAngle: pi / 2, endAngle: pi),
            BorderSegment(
                length: max(0, height - 2 * radius), isArc: false,
                startPoint: CGPoint(x: inset, y: inset + height - radius),
                endPoint:   CGPoint(x: inset, y: inset + radius)),
            BorderSegment(
                length: pi / 2 * radius, isArc: true,
                center: CGPoint(x: inset + radius, y: inset + radius),
                radius: radius, startAngle: pi, endAngle: 3 * pi / 2)
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
        // fallback：夾回最後一個 segment 的末端，避免負值
        return (segments.count - 1, segments.last?.length ?? 0)
    }

    // MARK: - Reset

    func reset() {
        smoothedLeft       = 0
        smoothedRight      = 0
        lastAmplitudeLeft  = 0
        lastAmplitudeRight = 0
        scaleGhosts.forEach { $0.node.removeFromParent() }
        scaleGhosts = []
    }

    // MARK: - Helper Structs & Methods

    private struct BorderSegment {
        var length:     CGFloat
        var isArc:      Bool
        var startPoint: CGPoint = .zero
        var endPoint:   CGPoint = .zero
        var center:     CGPoint = .zero
        var radius:     CGFloat = 0
        var startAngle: CGFloat = 0
        var endAngle:   CGFloat = 0

        func point(at t: CGFloat) -> CGPoint {
            if isArc {
                let angle = startAngle + (endAngle - startAngle) * t
                return CGPoint(x: center.x + radius * cos(angle),
                               y: center.y + radius * sin(angle))
            } else {
                return CGPoint(
                    x: startPoint.x + (endPoint.x - startPoint.x) * t,
                    y: startPoint.y + (endPoint.y - startPoint.y) * t
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
