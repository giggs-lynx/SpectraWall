//
//  AudioDataBus.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import Combine
import Foundation

struct StereoBins {
    let left: [Float]
    let right: [Float]

    // MARK: - Amplitude Helpers

    func leftAmplitude(binRange: Range<Int> = 0..<8) -> Float {
        let slice = left[binRange.clamped(to: left.indices)]
        guard !slice.isEmpty else { return 0 }
        return slice.reduce(0, +) / Float(slice.count)
    }

    func rightAmplitude(binRange: Range<Int> = 0..<8) -> Float {
        let slice = right[binRange.clamped(to: right.indices)]
        guard !slice.isEmpty else { return 0 }
        return slice.reduce(0, +) / Float(slice.count)
    }

    func amplitude(for channelMode: ChannelMode, binRange: Range<Int> = 0..<8) -> Float {
        switch channelMode {
        case .stereo, .mono:
            return (leftAmplitude(binRange: binRange) + rightAmplitude(binRange: binRange)) / 2
        case .left:
            return leftAmplitude(binRange: binRange)
        case .right:
            return rightAmplitude(binRange: binRange)
        }
    }

    /// Peak across the full spectrum (both channels). Silence detection uses peak
    /// rather than a band average so vocal/hi-hat passages with no bass content
    /// don't read as silent; combined L/R so both channels gate together.
    var peak: Float {
        max(left.max() ?? 0, right.max() ?? 0)
    }
}

/// Full-spectrum peak thresholds for silence detection, shared by OrbEffect's
/// silence gate and AudioActivityMonitor's hysteresis so they never drift apart.
enum SilenceThreshold {
    /// Peak below this reads as silent.
    static let enter: Float = 0.001
    /// Peak above this reads as active. The gap is the hysteresis band.
    static let exit: Float = 0.01
}

class AudioDataBus {
    static let shared = AudioDataBus()

    let spectrumPublisher = PassthroughSubject<StereoBins, Never>()
    let resetPublisher = PassthroughSubject<Void, Never>()

    /// CACurrentMediaTime() at which the most-recent spectrumPublisher.send() ran.
    /// Subscribers can compare their processing time against this to detect queue
    /// backlog (sink processing time well after source emit = events piled up).
    /// Updated immediately before send so subscribers see latest value.
    var lastSourceEmitTime: TimeInterval = 0

    /// Monotonic counter incremented before every spectrumPublisher.send().
    /// A sink tracking its own processed count and reading this gives the exact
    /// number of events queued ahead of its current task — direct backlog measure.
    var sourceEventCount: UInt64 = 0

    private init() {}
}
