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
}

class AudioDataBus {
    static let shared = AudioDataBus()

    let spectrumPublisher = PassthroughSubject<StereoBins, Never>()
    let amplitudePublisher = PassthroughSubject<Float, Never>()
    let resetPublisher = PassthroughSubject<Void, Never>()
}
