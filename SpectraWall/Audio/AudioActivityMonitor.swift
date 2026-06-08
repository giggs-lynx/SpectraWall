//
//  AudioActivityMonitor.swift
//  SpectraWall
//
//  Bridges the background-thread spectrum feed to main-thread observables that
//  drive (a) the popover's level meter and (b) the animated menu-bar icon. There
//  is no existing published level — each effect computes its own privately — so
//  this is the one shared feed.
//
//  Two outputs, five bands (matching the five bars in the app icon):
//   - bands:    audio level, decays to 0 on silence. Popover meter (flat+grey when quiet).
//   - iconBars: same audio while playing, but eases back to the icon's resting
//               spectrum shape on silence, so the menu-bar icon settles into its
//               recognizable logo instead of going flat.
//   - isSilent: the SAME metric the effects use (full-spectrum peak) with Orb's
//               proven hysteresis thresholds.
//
//  Runs for the app's lifetime (the menu-bar icon must animate whenever audio
//  plays). Publishing is skipped once values settle, so a quiet source costs only
//  the bare timer tick — no observer churn, no icon redraw.
//

import Combine
import Foundation
import QuartzCore

final class AudioActivityMonitor: ObservableObject {
    static let shared = AudioActivityMonitor()

    /// Normalized 0...1 bar heights, low→high frequency. Popover meter.
    @Published private(set) var bands: [Double]
    /// Normalized 0...1 bar heights for the menu-bar icon — rests at `restingHeights`.
    @Published private(set) var iconBars: [Double]
    /// Hysteresis-debounced silence state.
    @Published private(set) var isSilent: Bool = true

    /// The icon's static spectrum shape (low→high), shown when silent.
    let restingHeights: [Double] = [0.42, 0.62, 0.88, 0.66, 0.50]

    // Frequency bands over the 96 chromatic bins (low → high), one per icon bar.
    private let bandRanges: [Range<Int>] = [0..<5, 5..<13, 13..<28, 28..<52, 52..<96]

    // Silence thresholds on full-spectrum peak — mirrors OrbEffect's silence gate.
    private let silenceEnter: Float = 0.001
    private let silenceExit: Float = 0.01
    private let staleTimeout: TimeInterval = 0.3

    // Written on `sinkQueue` (sink), read on main (tick). Plain scalars/small
    // arrays — a torn read just yields a slightly stale meter frame.
    private var rawBands: [Float]
    private var rawPeak: Float = 0
    private var lastEmit: TimeInterval = 0

    // The spectrum feed is published on the Core Audio real-time thread; effects
    // hop off it via renderQueue before doing any work. Mirror that here so the
    // band reduction never runs inline on the RT thread.
    private let sinkQueue = DispatchQueue(label: "com.spectrawall.audioActivityMonitor", qos: .utility)

    // Main-thread smoothing state.
    private var smoothed: [Double]
    private var iconSmoothed: [Double]
    private var agc: Float = 0.05
    private let agcFloor: Float = 0.02
    private let publishEpsilon = 0.004

    private var started = false
    private var cancellable: AnyCancellable?
    private var timer: Timer?

    private init() {
        let n = bandRanges.count
        bands = Array(repeating: 0, count: n)
        iconBars = restingHeights
        smoothed = Array(repeating: 0, count: n)
        iconSmoothed = restingHeights
        rawBands = Array(repeating: 0, count: n)

        cancellable = AudioDataBus.shared.spectrumPublisher
            .receive(on: sinkQueue)
            .sink { [weak self] bins in
                guard let self, self.started else { return }
                for (i, range) in self.bandRanges.enumerated() {
                    let l = bins.leftAmplitude(binRange: range)
                    let r = bins.rightAmplitude(binRange: range)
                    self.rawBands[i] = max(l, r)
                }
                self.rawPeak = max(bins.left.max() ?? 0, bins.right.max() ?? 0)
                self.lastEmit = CACurrentMediaTime()
            }
    }

    /// Begin driving the meters. Idempotent; called once at launch.
    func start() {
        guard !started else { return }
        started = true
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let stale = CACurrentMediaTime() - lastEmit > staleTimeout

        // Silence hysteresis on the full-spectrum peak.
        let nowSilent: Bool
        if stale || rawPeak < silenceEnter {
            nowSilent = true
        } else if rawPeak > silenceExit {
            nowSilent = false
        } else {
            nowSilent = isSilent
        }
        if nowSilent != isSilent { isSilent = nowSilent }

        // Auto-gain: rise instantly to the loudest band, decay slowly, floored so a
        // near-silent floor doesn't get amplified into full bars.
        let maxRaw = rawBands.max() ?? 0
        agc = max(agcFloor, max(maxRaw, agc * 0.92))

        var newBands = smoothed
        var newIcon = iconSmoothed
        for i in smoothed.indices {
            // Popover: audio level, → 0 when silent.
            let bandTarget = (stale || nowSilent) ? 0 : Double(min(1, rawBands[i] / agc))
            newBands[i] += (bandTarget - smoothed[i]) * (bandTarget > smoothed[i] ? 0.5 : 0.18)

            // Menu-bar: same audio, but rest at the logo shape when silent.
            let iconTarget = (stale || nowSilent) ? restingHeights[i] : Double(min(1, rawBands[i] / agc))
            newIcon[i] += (iconTarget - iconSmoothed[i]) * (iconTarget > iconSmoothed[i] ? 0.45 : 0.2)
        }
        smoothed = newBands
        iconSmoothed = newIcon

        // Publish only on meaningful change so a settled (quiet) source stops all
        // observer churn and icon redraws.
        if !nearlyEqual(newBands, bands) { bands = newBands }
        if !nearlyEqual(newIcon, iconBars) { iconBars = newIcon }
    }

    private func nearlyEqual(_ a: [Double], _ b: [Double]) -> Bool {
        guard a.count == b.count else { return false }
        for i in a.indices where abs(a[i] - b[i]) > publishEpsilon { return false }
        return true
    }
}
