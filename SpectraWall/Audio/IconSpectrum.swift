//
//  IconSpectrum.swift
//  SpectraWall
//
//  Single source of truth for the five-bar spectrum glyph's identity: how many
//  bars there are, which frequency band each bar summarises, and the resting
//  "logo" shape the menu-bar icon settles into on silence. The band reduction
//  (AudioActivityMonitor), the menu-bar icon (AppDelegate), and the popover
//  meter (AudioActivityBars) all derive their bar count from here — change the
//  glyph in this one file. Bar pixel geometry stays component-local on purpose.
//

import Foundation

enum IconSpectrum {
    /// Frequency bands over the analyzer's 96 chromatic bins (low → high),
    /// one per bar.
    static let bandRanges: [Range<Int>] = [0..<5, 5..<13, 13..<28, 28..<52, 52..<96]

    /// The icon's static spectrum shape (low → high), shown when silent.
    /// Must stay in lockstep with `bandRanges` — IconSpectrumTests pins it.
    static let restingHeights: [Double] = [0.42, 0.62, 0.88, 0.66, 0.50]
}
