//
//  SliderSpec.swift
//  SpectraWall
//
//  Single source of truth for each slider parameter's range / step / default.
//  Drives three things that used to repeat the same literals: the slider UI,
//  double-click-to-reset, and Randomize. Numeric ranges here mirror the literals
//  that previously lived inline at every SettingsSlider call site.
//

import AppKit

struct SliderSpec {
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double

    /// Clamp into range, then quantize to the nearest step. Used for typed input
    /// and randomization so both honour the same bounds as the slider.
    func snapped(_ raw: Double) -> Double {
        SliderSpec.snap(raw, range: range, step: step)
    }

    /// A random in-range value, quantized to step.
    func random() -> Double {
        snapped(Double.random(in: range))
    }

    /// Free function so SettingsSlider can snap typed input without a SliderSpec
    /// (the 4 non-effect call sites still pass range/step directly).
    static func snap(_ raw: Double, range: ClosedRange<Double>, step: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }
        let steps = ((clamped - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
    }
}

// MARK: - Per-effect specs

enum SpectrumSpec {
    static let gain = SliderSpec(range: 0.5...3.0, step: 0.1, defaultValue: 2.6)
    static let maxHeight = SliderSpec(range: 0.1...1.0, step: 0.05, defaultValue: 0.35)
    static let width = SliderSpec(range: 0.1...1.0, step: 0.05, defaultValue: 1.0)
    static let powerCurve = SliderSpec(range: 1.0...3.0, step: 0.1, defaultValue: 2.0)
    static let attack = SliderSpec(range: 0.5...1.0, step: 0.05, defaultValue: 0.95)
    static let release = SliderSpec(range: 0.1...0.5, step: 0.05, defaultValue: 0.2)
}

enum RadialSpectrumSpec {
    static let gain = SliderSpec(range: 0.5...3.0, step: 0.1, defaultValue: 2.6)
    static let powerCurve = SliderSpec(range: 1.0...3.0, step: 0.1, defaultValue: 2.0)
    static let attack = SliderSpec(range: 0.5...1.0, step: 0.05, defaultValue: 0.95)
    static let release = SliderSpec(range: 0.1...0.5, step: 0.05, defaultValue: 0.2)
    static let innerRadius = SliderSpec(range: 40...300, step: 5, defaultValue: 120)
    static let maxExtent = SliderSpec(range: 20...200, step: 5, defaultValue: 80)
}

enum OrbSpec {
    static let boost = SliderSpec(range: 1.0...6.0, step: 0.1, defaultValue: 3.0)
    static let attack = SliderSpec(range: 0.3...1.0, step: 0.05, defaultValue: 0.95)
    static let release = SliderSpec(range: 0.1...0.5, step: 0.05, defaultValue: 0.4)
    static let baseRadius = SliderSpec(range: 40...300, step: 5, defaultValue: 80)
    static let outerRadiusMultiplier = SliderSpec(range: 1.0...3.0, step: 0.1, defaultValue: 1.4)
    static let outerOpacity = SliderSpec(range: 0.0...1.0, step: 0.05, defaultValue: 0.15)
    static let rippleSpeed = SliderSpec(range: 0.5...4.0, step: 0.1, defaultValue: 1.5)
    static let rippleOpacity = SliderSpec(range: 0.0...1.0, step: 0.05, defaultValue: 0.5)
    static let rippleDuration = SliderSpec(range: 0.3...4.0, step: 0.1, defaultValue: 2.0)
    static let rippleThreshold = SliderSpec(range: 1.0...3.0, step: 0.1, defaultValue: 1.6)
    static let blobAmount = SliderSpec(range: 0.0...0.8, step: 0.05, defaultValue: 0.0)
    static let hueCycleSpeed = SliderSpec(range: 0.0...0.5, step: 0.01, defaultValue: 0.0)
}

enum WaveformSpec {
    static let windowSeconds = SliderSpec(range: 1.0...10.0, step: 0.5, defaultValue: 3.0)
    static let gain = SliderSpec(range: 0.5...8.0, step: 0.1, defaultValue: 2.0)
    static let maxHeight = SliderSpec(range: 0.05...0.5, step: 0.01, defaultValue: 0.2)
}

enum AmbientGlowSpec {
    static let size = SliderSpec(range: 0.05...0.4, step: 0.01, defaultValue: 0.15)
    static let intensity = SliderSpec(range: 0.0...1.0, step: 0.05, defaultValue: 0.5)
    static let attack = SliderSpec(range: 0.3...1.0, step: 0.05, defaultValue: 0.95)
    static let release = SliderSpec(range: 0.1...0.5, step: 0.05, defaultValue: 0.4)
}

enum BorderSpec {
    static let speed = SliderSpec(range: 0.01...0.5, step: 0.01, defaultValue: 0.05)
    static let tailLength = SliderSpec(range: 0.05...1.0, step: 0.05, defaultValue: 0.15)
    static let baseWidth = SliderSpec(range: 1.0...50.0, step: 0.5, defaultValue: 20.0)
    static let cornerRadius = SliderSpec(range: 0...100, step: 5, defaultValue: 20.0)
    static let pulseAttack = SliderSpec(range: 0.05...1.0, step: 0.05, defaultValue: 0.85)
    static let pulseRelease = SliderSpec(range: 0.05...1.0, step: 0.05, defaultValue: 0.1)
    static let pulseFlash = SliderSpec(range: 0.0...1.0, step: 0.05, defaultValue: 0.7)
    static let pulseSpeedBoost = SliderSpec(range: 0.0...3.0, step: 0.1, defaultValue: 0.0)
    static let widthBreath = SliderSpec(range: 0.0...1.0, step: 0.05, defaultValue: 0.0)
    static let ghostSize = SliderSpec(range: 0.0...2.0, step: 0.1, defaultValue: 0.9)
    static let ghostOpacity = SliderSpec(range: 0.0...1.0, step: 0.05, defaultValue: 0.65)
    static let ghostDuration = SliderSpec(range: 0.1...1.5, step: 0.1, defaultValue: 0.3)
}

// MARK: - Pleasant random colours

/// Hue-based random colours for Randomize — high saturation/brightness so the
/// result always looks deliberate rather than muddy. relatedPair keeps two
/// colours in the same neighbourhood for gradient/head-tail pairs.
enum RandomColor {
    static func pleasant() -> ColorData {
        color(hue: Double.random(in: 0...1))
    }

    static func relatedPair() -> (ColorData, ColorData) {
        let base = Double.random(in: 0...1)
        let offset = Double.random(in: 0.04...0.12) * (Bool.random() ? 1 : -1)
        let partner = (base + offset).truncatingRemainder(dividingBy: 1.0)
        return (color(hue: base), color(hue: partner < 0 ? partner + 1 : partner))
    }

    private static func color(hue: Double) -> ColorData {
        ColorData(NSColor(
            hue: CGFloat(hue),
            saturation: CGFloat(Double.random(in: 0.7...1.0)),
            brightness: CGFloat(Double.random(in: 0.85...1.0)),
            alpha: 1.0
        ))
    }
}
