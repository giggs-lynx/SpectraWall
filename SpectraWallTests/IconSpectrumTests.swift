//
//  IconSpectrumTests.swift
//  SpectraWallTests
//
//  Pins the five-bar glyph's internal consistency. These arrays used to live
//  apart and stayed aligned by convention only; this test makes the contract
//  executable so changing the bar count in one place fails loudly.
//

import XCTest
@testable import SpectraWall

final class IconSpectrumTests: XCTestCase {

    func testRestingShapeMatchesBandCount() {
        XCTAssertEqual(IconSpectrum.restingHeights.count, IconSpectrum.bandRanges.count)
    }

    func testRestingHeightsAreNormalized() {
        for h in IconSpectrum.restingHeights {
            XCTAssertTrue((0...1).contains(h), "resting height \(h) outside 0...1")
        }
    }

    /// Bands must tile the analyzer's bin range exactly: contiguous, ascending,
    /// starting at 0 and ending at the analyzer's binCount (96 — the default
    /// AudioEngine passes to AudioAnalyzer).
    func testBandRangesTileTheAnalyzerBins() {
        var expectedStart = 0
        for range in IconSpectrum.bandRanges {
            XCTAssertEqual(range.lowerBound, expectedStart, "gap or overlap before \(range)")
            XCTAssertFalse(range.isEmpty, "empty band \(range)")
            expectedStart = range.upperBound
        }
        XCTAssertEqual(expectedStart, 96)
    }
}
