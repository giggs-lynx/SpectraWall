//
//  AudioDataBus.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import Combine

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
}

class AudioDataBus {
    static let shared = AudioDataBus()

    let spectrumPublisher = PassthroughSubject<StereoBins, Never>()
    let resetPublisher = PassthroughSubject<Void, Never>()

    private init() {}
}
