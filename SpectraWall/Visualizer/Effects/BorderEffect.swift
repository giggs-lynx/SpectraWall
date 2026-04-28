//
//  BorderEffect.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SpriteKit
import Combine

class BorderEffect: SKNode {
    private var cancellables = Set<AnyCancellable>()
    private var sceneSize: CGSize = .zero
    private var settings: LayerSettings

    private var borderSettings: BorderSettings {
        settings.effectSettings as? BorderSettings ?? .defaults
    }

    private struct StrokeState {
        var progress: Double = 0.0
        var nodes: [SKShapeNode] = []
    }
    private var strokes: [StrokeState] = []

    private var smoothedAmplitude: Float = 0
    private var lastUpdateTime: TimeInterval = 0
    private var perimeterLength: CGFloat = 0

    private var segmentCache: [BorderSegment]? = nil
    private var cachedSceneSize: CGSize = .zero
    private var cachedCornerRadius: Double = -1

    private let trailSegments = 20

    init(size: CGSize, settings: LayerSettings) {
        self.sceneSize = size
        self.settings = settings
        super.init()
        setupStrokes()
        subscribeToAudio()
        observeSettings()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func observeSettings() {
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupStrokes()
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupStrokes() {
        segmentCache = nil  // 強制重建 segments

        strokes.forEach { $0.nodes.forEach { $0.removeFromParent() } }
        strokes = []

        let count = borderSettings.strokeCount
        for i in 0..<count {
            var state = StrokeState()
            state.progress = count == 2 ? Double(i) * 0.5 : 0.0

            for j in 0..<trailSegments {
                let node = SKShapeNode()
                node.lineWidth = 0
                node.lineCap = .round
                let alpha = CGFloat(j) / CGFloat(trailSegments - 1)
                node.alpha = alpha
                node.blendMode = .add
                addChild(node)
                state.nodes.append(node)
            }
            strokes.append(state)
        }

        updatePerimeterLength()
        alpha = CGFloat(settings.opacity)
    }

    private func updatePerimeterLength() {
        let w = sceneSize.width
        let h = sceneSize.height
        let r = CGFloat(borderSettings.cornerRadius)
        let straightLength = 2 * (w - 2 * r) + 2 * (h - 2 * r)
        let cornerLength = 2 * .pi * r
        perimeterLength = straightLength + cornerLength
    }

    // MARK: - Audio

    private func subscribeToAudio() {
        AudioDataBus.shared.amplitudePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] amplitude in
                guard let self else { return }
                let coeff = amplitude > self.smoothedAmplitude
                    ? Float(self.borderSettings.pulseAttack)
                    : Float(self.borderSettings.pulseRelease)
                self.smoothedAmplitude = self.smoothedAmplitude * (1 - coeff) + amplitude * coeff
            }
            .store(in: &cancellables)
    }

    // MARK: - Update

    func update(_ currentTime: TimeInterval) {
        guard lastUpdateTime > 0 else {
            lastUpdateTime = currentTime
            return
        }

        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        let bs = borderSettings
        let delta = bs.speed * dt * (bs.clockwise ? 1 : -1)

        for i in 0..<strokes.count {
            strokes[i].progress = (strokes[i].progress + delta).truncatingRemainder(dividingBy: 1.0)
            if strokes[i].progress < 0 { strokes[i].progress += 1.0 }
            renderStroke(index: i)
        }
    }

    private func renderStroke(index: Int) {
        let stroke = strokes[index]
        let bs = borderSettings
        let clockwise = bs.clockwise

        // 順時針：j=trailSegments-1 是頭，j=0 是尾
        // 逆時針：j=0 是頭，j=trailSegments-1 是尾
        let colorStart = index == 0 ? bs.stroke1ColorStart : bs.stroke2ColorStart
        let colorEnd = index == 0 ? bs.stroke1ColorEnd : bs.stroke2ColorEnd
        let tailLength = bs.tailLength
        let pulseWidth = CGFloat(smoothedAmplitude) * 8.0
        let baseWidth = CGFloat(bs.baseWidth) + pulseWidth

        for j in 0..<trailSegments {
            let node = stroke.nodes[j]

            // t=1 是頭部（最亮、最寬），t=0 是尾部
            let t: Double = clockwise
                ? Double(j) / Double(trailSegments - 1)
                : 1.0 - Double(j) / Double(trailSegments - 1)

            // 頭部在 progress，尾巴往反方向延伸
            let offset = clockwise
                ? -(1.0 - t) * tailLength
                : (1.0 - t) * tailLength

            let segProgress = stroke.progress + offset
            let adjustedProgress = ((segProgress.truncatingRemainder(dividingBy: 1.0)) + 1.0).truncatingRemainder(dividingBy: 1.0)

            let segLength = perimeterLength * CGFloat(tailLength) / CGFloat(trailSegments)
            let path = borderPath(from: adjustedProgress, length: segLength, clockwise: clockwise)
            node.path = path

            let color = interpolateColor(
                from: colorEnd.nsColor,
                to: colorStart.nsColor,
                t: CGFloat(t)
            )
            node.strokeColor = color
            node.lineWidth = baseWidth * CGFloat(t)
        }
    }

    // MARK: - Path

    private func borderPath(from progress: Double, length: CGFloat, clockwise: Bool) -> CGPath {
        let path = CGMutablePath()
        var drawn: CGFloat = 0
        var current = CGFloat(progress) * perimeterLength
        var started = false
        let segments = borderSegments()

        while drawn < length {
            let wrapped = current.truncatingRemainder(dividingBy: perimeterLength)
            let (segIndex, localDist) = segmentAt(distance: wrapped, segments: segments)
            let seg = segments[segIndex]
            let remaining = seg.length - localDist
            let toDraw = min(remaining, length - drawn)
            let startT = localDist / seg.length
            let endT = (localDist + toDraw) / seg.length

            if !started {
                path.move(to: seg.point(at: startT))
                started = true
            }

            if seg.isArc {
                let startAngle = seg.startAngle + (seg.endAngle - seg.startAngle) * startT
                let endAngle = seg.startAngle + (seg.endAngle - seg.startAngle) * endT
                path.addArc(
                    center: seg.center,
                    radius: seg.radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: !clockwise
                )
            } else {
                path.addLine(to: seg.point(at: endT))
            }

            drawn += toDraw
            current += toDraw
        }

        return path
    }

    // MARK: - Border Geometry

    private struct BorderSegment {
        var length: CGFloat
        var isArc: Bool
        var startPoint: CGPoint = .zero
        var endPoint: CGPoint = .zero
        var center: CGPoint = .zero
        var radius: CGFloat = 0
        var startAngle: CGFloat = 0
        var endAngle: CGFloat = 0

        func point(at t: CGFloat) -> CGPoint {
            if isArc {
                let angle = startAngle + (endAngle - startAngle) * t
                return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            } else {
                return CGPoint(
                    x: startPoint.x + (endPoint.x - startPoint.x) * t,
                    y: startPoint.y + (endPoint.y - startPoint.y) * t
                )
            }
        }
    }

    private func borderSegments() -> [BorderSegment] {
        if let cache = segmentCache,
           cachedSceneSize == sceneSize,
           cachedCornerRadius == borderSettings.cornerRadius {
            return cache
        }

        let w = sceneSize.width
        let h = sceneSize.height
        let r = CGFloat(borderSettings.cornerRadius)
        let pi = CGFloat.pi

        var segs: [BorderSegment] = []

        segs.append(BorderSegment(length: w - 2*r, isArc: false, startPoint: CGPoint(x: r, y: 0), endPoint: CGPoint(x: w-r, y: 0)))
        segs.append(BorderSegment(length: pi/2*r, isArc: true, center: CGPoint(x: w-r, y: r), radius: r, startAngle: -pi/2, endAngle: 0))
        segs.append(BorderSegment(length: h - 2*r, isArc: false, startPoint: CGPoint(x: w, y: r), endPoint: CGPoint(x: w, y: h-r)))
        segs.append(BorderSegment(length: pi/2*r, isArc: true, center: CGPoint(x: w-r, y: h-r), radius: r, startAngle: 0, endAngle: pi/2))
        segs.append(BorderSegment(length: w - 2*r, isArc: false, startPoint: CGPoint(x: w-r, y: h), endPoint: CGPoint(x: r, y: h)))
        segs.append(BorderSegment(length: pi/2*r, isArc: true, center: CGPoint(x: r, y: h-r), radius: r, startAngle: pi/2, endAngle: pi))
        segs.append(BorderSegment(length: h - 2*r, isArc: false, startPoint: CGPoint(x: 0, y: h-r), endPoint: CGPoint(x: 0, y: r)))
        segs.append(BorderSegment(length: pi/2*r, isArc: true, center: CGPoint(x: r, y: r), radius: r, startAngle: pi, endAngle: 3*pi/2))

        segmentCache = segs
        cachedSceneSize = sceneSize
        cachedCornerRadius = borderSettings.cornerRadius
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

    // MARK: - Helpers

    private func interpolateColor(from: NSColor, to: NSColor, t: CGFloat) -> NSColor {
        let r = from.redComponent + (to.redComponent - from.redComponent) * t
        let g = from.greenComponent + (to.greenComponent - from.greenComponent) * t
        let b = from.blueComponent + (to.blueComponent - from.blueComponent) * t
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
