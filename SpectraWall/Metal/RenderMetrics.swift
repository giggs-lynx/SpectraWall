//
//  RenderMetrics.swift
//  SpectraWall
//
//  Always-on per-renderer frame-time + callback-gap meter. Logs a one-line
//  heartbeat every ~2s at info level to AppLog.render. OSLog `.info` is
//  free when no subscriber is attached, so this stays in production at
//  zero cost; running
//
//      log show --predicate 'subsystem == "com.spectrawall.app"
//                            AND category == "Render"' --info --last 5m
//
//  surfaces it on demand.
//
//  Two measurements per renderer:
//   - **render time**: wall-clock between `recordFrame(start:end:)` markers
//     (i.e. how long the draw pass took on renderQueue). Anomaly: ≥ 8ms on
//     ProMotion, ≥ 16ms on 60Hz means CPU encode is the bottleneck.
//   - **callback gap**: interval between consecutive recordCallback calls
//     (vsync delivery rate). Anomaly: gap >> 1/refreshRate means the runloop
//     is starved (e.g. multiple displayLinks sharing one runloop).
//

import OSLog
import QuartzCore

final class RenderMetrics {

    let displayID: CGDirectDisplayID

    private let log: Logger
    private let windowDuration: TimeInterval
    private let slowFrameThreshold: TimeInterval

    // Frame stats
    private var frameCount = 0
    private var slowFrames = 0
    private var totalRenderTime: Double = 0
    private var maxRenderTime: Double = 0

    // Callback-gap stats
    private var lastCallback: TimeInterval = 0
    private var maxCallbackGap: TimeInterval = 0
    private var totalCallbackGap: Double = 0
    private var callbackCount = 0

    private var windowStart: TimeInterval = 0

    init(displayID: CGDirectDisplayID,
         log: Logger = AppLog.render,
         windowDuration: TimeInterval = 2.0,
         slowFrameThreshold: TimeInterval = 0.008) {
        self.displayID = displayID
        self.log = log
        self.windowDuration = windowDuration
        self.slowFrameThreshold = slowFrameThreshold
    }

    /// Record a displayLink callback arrival. Sample at the very top of the
    /// delegate method so the recorded gap reflects what the runloop saw,
    /// not how long the draw work took.
    func recordCallback(at time: TimeInterval) {
        if lastCallback > 0 {
            let gap = time - lastCallback
            totalCallbackGap += gap
            if gap > maxCallbackGap { maxCallbackGap = gap }
            callbackCount += 1
        }
        lastCallback = time
    }

    /// Record a draw pass. Call with `start` captured at the entry of draw()
    /// and `end` after commandBuffer.commit(). Emits a heartbeat log line if
    /// the rolling window has elapsed.
    func recordFrame(start: TimeInterval, end: TimeInterval) {
        let renderTime = end - start
        frameCount += 1
        totalRenderTime += renderTime
        if renderTime > maxRenderTime { maxRenderTime = renderTime }
        if renderTime > slowFrameThreshold { slowFrames += 1 }
        if windowStart == 0 { windowStart = end }
        let elapsed = end - windowStart
        if elapsed >= windowDuration {
            emit(elapsed: elapsed)
            reset(windowStart: end)
        }
    }

    private func emit(elapsed: TimeInterval) {
        let avgMs = totalRenderTime / Double(frameCount) * 1000
        let maxMs = maxRenderTime * 1000
        let slowPct = Double(slowFrames) / Double(frameCount) * 100
        let fps = Double(frameCount) / elapsed
        let avgGapMs = callbackCount > 0
            ? (totalCallbackGap / Double(callbackCount) * 1000)
            : 0
        let maxGapMs = maxCallbackGap * 1000
        let id = displayID
        let cnt = frameCount
        let slowCnt = slowFrames
        log.info(
            """
            [perf] display=\(id, privacy: .public) fps=\(fps, privacy: .public) \
            avg=\(avgMs, privacy: .public)ms max=\(maxMs, privacy: .public)ms \
            slow8ms=\(slowPct, privacy: .public)% (\(slowCnt, privacy: .public)/\(cnt, privacy: .public)) \
            cb-gap-avg=\(avgGapMs, privacy: .public)ms cb-gap-max=\(maxGapMs, privacy: .public)ms
            """
        )
    }

    private func reset(windowStart: TimeInterval) {
        frameCount = 0
        slowFrames = 0
        totalRenderTime = 0
        maxRenderTime = 0
        maxCallbackGap = 0
        totalCallbackGap = 0
        callbackCount = 0
        self.windowStart = windowStart
    }
}
