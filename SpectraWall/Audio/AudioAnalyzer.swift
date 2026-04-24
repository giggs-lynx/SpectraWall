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

    let attackCoeff: Float = 0.8
    let releaseCoeff: Float = 0.15

    init(fftSize: Int = 1024, binCount: Int = 32) {
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

    func analyze(_ samples: [Float]) -> [Float] {
        // 1. 確保長度足夠，不足補零
        var input = samples.count >= fftSize
            ? Array(samples.prefix(fftSize))
            : samples + [Float](repeating: 0, count: fftSize - samples.count)

        // 2. 套用 Hanning window
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(fftSize))

        // 3. FFT
        var realPart = input
        var imagPart = [Float](repeating: 0, count: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var complex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                vDSP_fft_zrip(fftSetup, &complex, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&complex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // 5. 對數刻度分組（Mel-like）
        let bins = melScaleBins(magnitudes: magnitudes)

        // 6. Attack/Release smoothing
        for i in 0..<binCount {
            let coeff = bins[i] > smoothed[i] ? attackCoeff : releaseCoeff
            smoothed[i] = smoothed[i] * (1 - coeff) + bins[i] * coeff
        }

        return smoothed
    }

    // MARK: - Mel Scale Grouping

    private func melScaleBins(magnitudes: [Float]) -> [Float] {
        let nyquist = Float(fftSize / 2)
        let minMel = melScale(20)
        let maxMel = melScale(20000)

        var bins = [Float](repeating: 0, count: binCount)

        for i in 0..<binCount {
            let melLow  = minMel + (maxMel - minMel) * Float(i) / Float(binCount)
            let melHigh = minMel + (maxMel - minMel) * Float(i + 1) / Float(binCount)
            let freqLow  = inverseMelScale(melLow)
            let freqHigh = inverseMelScale(melHigh)

            let idxLow  = Int(freqLow  / 20000 * nyquist)
            let idxHigh = Int(freqHigh / 20000 * nyquist)
            let low  = max(0, min(idxLow,  magnitudes.count - 1))
            let high = max(low + 1, min(idxHigh, magnitudes.count))

            var sum: Float = 0
            vDSP_sve(Array(magnitudes[low..<high]), 1, &sum, vDSP_Length(high - low))
            bins[i] = sum / Float(high - low)
        }

        // Normalize 到 0.0 ~ 1.0
        var maxVal: Float = 0
        vDSP_maxv(bins, 1, &maxVal, vDSP_Length(binCount))
        if maxVal > 0 {
            vDSP_vsdiv(bins, 1, &maxVal, &bins, 1, vDSP_Length(binCount))
        }

        return bins
    }

    private func melScale(_ freq: Float) -> Float {
        return 2595 * log10(1 + freq / 700)
    }

    private func inverseMelScale(_ mel: Float) -> Float {
        return 700 * (pow(10, mel / 2595) - 1)
    }
}
