//
//  AudioDataBus.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import Combine

class AudioDataBus {
    static let shared = AudioDataBus()

    let spectrumPublisher = PassthroughSubject<[Float], Never>()
    let amplitudePublisher = PassthroughSubject<Float, Never>()
    let resetPublisher = PassthroughSubject<Void, Never>()
}
