//
//  AudioAnalyzer.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import Accelerate

class AudioAnalyzer {
    private let fftSize: Int
    private let binCount: Int
    private var fftSetup: FFTSetup
    private var window: [Float]
    private var smoothed: [Float]
    private var sampleBuffer: [Float] = []

    let attackCoeff: Float = 0.95  // 原本 0.8，上升更快更直接
    let releaseCoeff: Float = 0.2  // 原本 0.3，下降也快一點

    init(fftSize: Int = 4096, binCount: Int = 96) {
        self.fftSize = fftSize
        self.binCount = binCount
        self.fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        self.smoothed = [Float](repeating: 0, count: binCount)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func analyze(_ samples: [Float]) -> [Float]? {
        sampleBuffer.append(contentsOf: samples)
        guard sampleBuffer.count >= fftSize else { return nil }

        let input = Array(sampleBuffer.suffix(fftSize))
        sampleBuffer = Array(sampleBuffer.suffix(fftSize / 2))

        return process(input)
    }

    // MARK: - Private

    private func process(_ samples: [Float]) -> [Float] {
        let settings = VisualizerSettings.shared
        
        // 1. 套用 Hanning window
        var windowed = samples
        vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // 2. FFT
        var realPart = windowed
        var imagPart = [Float](repeating: 0, count: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var complex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                vDSP_fft_zrip(fftSetup, &complex, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&complex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // 3. 正規化
        var scale = Float(fftSize)
        vDSP_vsdiv(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))

        // 4. Chromatic scale 分組
        let bins = chromaticScaleBins(magnitudes: magnitudes)

        // 5. Attack/Release smoothing
        for i in 0..<binCount {
            let coeff = bins[i] > smoothed[i]
                ? Float(settings.attackCoeff)
                : Float(settings.releaseCoeff)
            smoothed[i] = smoothed[i] * (1 - coeff) + bins[i] * coeff
        }

        return smoothed
    }

    // MARK: - Chromatic Scale Grouping

    private func chromaticScaleBins(magnitudes: [Float]) -> [Float] {
        let settings = VisualizerSettings.shared
        let sampleRate: Float = 48000
        let freqPerBin = sampleRate / Float(fftSize)

        // A0 = 27.5Hz から 96 半音（8 オクターブ）
        let baseFreq: Float = 27.5
        var bins = [Float](repeating: 0, count: binCount)

        for i in 0..<binCount {
            let freqLow  = baseFreq * pow(2, Float(i) / 12)
            let freqHigh = baseFreq * pow(2, Float(i + 1) / 12)

            let idxLow  = max(0, Int(freqLow  / freqPerBin))
            let idxHigh = min(magnitudes.count - 1, Int(freqHigh / freqPerBin))

            if idxHigh <= idxLow {
                bins[i] = magnitudes[max(0, idxLow)]
                continue
            }

            var sum: Float = 0
            let slice = Array(magnitudes[idxLow...idxHigh])
            vDSP_sve(slice, 1, &sum, vDSP_Length(slice.count))
            bins[i] = sum / Float(slice.count)
        }

        // 5. dB 轉換 + bass attenuation + normalize
        for i in 0..<binCount {
            let db = 20 * log10(max(bins[i], 1e-10))
            let bassAtten = Float(settings.bassAttenuation) * max(0, 1.0 - Float(i) / Float(binCount / 2))
            let adjusted = db - bassAtten
            bins[i] = max(0, min(1, (adjusted + 80) / 70))
            bins[i] = pow(bins[i], Float(settings.powerCurve))
        }

        return bins
    }
}
