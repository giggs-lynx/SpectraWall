//
//  LayerSettingsCodableTests.swift
//  SpectraWallTests
//
//  Round-trips LayerSettings through the descriptor-driven codec installed
//  in C5. Wire format must stay compatible with existing scene-<uuid>.json
//  files: EffectType.rawValue strings ("Spectrum" / "Orb" / "Border") must
//  continue to map to the right EffectSettings concrete type, and the
//  decoder must continue to accept legacy JSON containing a layer `id`
//  field even though the encoder no longer emits one.
//

import XCTest
@testable import SpectraWall

final class LayerSettingsCodableTests: XCTestCase {

    override static func setUp() {
        super.setUp()
        EffectRegistry.bootstrap()
    }

    func testSpectrumRoundTrip() throws {
        try assertRoundTrip(effectType: .spectrum, as: SpectrumSettings.self)
    }

    func testOrbRoundTrip() throws {
        try assertRoundTrip(effectType: .orb, as: OrbSettings.self)
    }

    func testBorderRoundTrip() throws {
        try assertRoundTrip(effectType: .border, as: BorderSettings.self)
    }

    /// Encoder no longer emits the `id` field, but pre-migration scene files
    /// have one. Decoder must preserve it onto the in-memory layer.
    func testDecoderPreservesLegacyIDField() throws {
        let storedID = try XCTUnwrap(UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"))
        let layer = LayerSettings(effectType: .spectrum, name: "Legacy")

        let encoded = try JSONEncoder().encode(layer)
        guard var json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            XCTFail("Encoded layer was not a JSON object")
            return
        }
        json["id"] = storedID.uuidString
        let withID = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(LayerSettings.self, from: withID)
        XCTAssertEqual(decoded.id, storedID)
        XCTAssertEqual(decoded.effectType, .spectrum)
    }

    /// Real scene JSON from a user-customised Orb layer (colours set via UI).
    /// Reproduces a complaint that refactor head decodes as default colours
    /// even though the JSON has the customised hex values.
    func testRealOrbLayerJSONPreservesCustomColors() throws {
        let jsonString = """
        {
          "channelMode": "stereo",
          "effectSettings": {
            "attack": 0.95,
            "baseRadius": 80,
            "boost": 3,
            "innerColorHigh": "#FFCC33FF",
            "innerColorLow": "#59B0053C",
            "outerColorHigh": "#FFCC33FF",
            "outerColorLow": "#FFFF0000",
            "outerOpacity": 0.15,
            "outerRadiusMultiplier": 1.4,
            "release": 0.4
          },
          "effectType": "Orb",
          "isVisible": true,
          "name": "Orb L",
          "opacity": 1.0,
          "positionX": 0.5,
          "positionY": 0.5
        }
        """
        let json = Data(jsonString.utf8)

        let layer = try JSONDecoder().decode(LayerSettings.self, from: json)
        XCTAssertEqual(layer.effectType, .orb)
        guard let orb = layer.effectSettings as? OrbSettings else {
            XCTFail("effectSettings is \(type(of: layer.effectSettings)), expected OrbSettings")
            return
        }
        // innerColorLow hex #59B0053C → AA=59 RR=B0 GG=05 BB=3C
        XCTAssertEqual(orb.innerColorLow.red, Double(0xB0) / 255, accuracy: 0.001,
                       "innerColorLow.red lost on decode — got \(orb.innerColorLow.red)")
        XCTAssertEqual(orb.innerColorLow.green, Double(0x05) / 255, accuracy: 0.001)
        XCTAssertEqual(orb.innerColorLow.blue, Double(0x3C) / 255, accuracy: 0.001)
    }

    /// Default encoded JSON has no `id`. The decoder should mint a fresh one.
    func testDecoderMintsFreshIDForJSONWithoutIDField() throws {
        let layer = LayerSettings(effectType: .orb)
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(LayerSettings.self, from: data)
        XCTAssertNotEqual(decoded.id, layer.id, "Encoder should not emit id; decoder must mint a fresh one")
    }

    private func assertRoundTrip<T: EffectSettings>(
        effectType: EffectType,
        as _: T.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let layer = LayerSettings(effectType: effectType, name: "Test \(effectType.rawValue)")
        layer.opacity = 0.7
        layer.positionX = 0.42
        layer.channelMode = .left
        layer.isVisible = false

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let firstData = try encoder.encode(layer)
        let decoded = try JSONDecoder().decode(LayerSettings.self, from: firstData)

        XCTAssertEqual(decoded.effectType, effectType, file: file, line: line)
        XCTAssertEqual(decoded.name, layer.name, file: file, line: line)
        XCTAssertEqual(decoded.opacity, layer.opacity, file: file, line: line)
        XCTAssertEqual(decoded.positionX, layer.positionX, file: file, line: line)
        XCTAssertEqual(decoded.channelMode, layer.channelMode, file: file, line: line)
        XCTAssertEqual(decoded.isVisible, layer.isVisible, file: file, line: line)
        XCTAssertTrue(decoded.effectSettings is T,
                      "effectSettings concrete type for \(effectType.rawValue) must be \(T.self)",
                      file: file, line: line)

        // Wire-format stability check. ColorData serialises as 8-bit ARGB hex,
        // so in-memory Float values quantise (e.g. 0.1 → 26/255 ≈ 0.10196)
        // and a strict Equatable comparison against the fresh defaults
        // would spuriously fail on the first round trip. Re-encoding the
        // decoded layer is the right invariant: second-pass JSON must match
        // first-pass JSON byte-for-byte.
        let secondData = try encoder.encode(decoded)
        XCTAssertEqual(secondData, firstData,
                       "Re-encoding a decoded layer must produce the same JSON",
                       file: file, line: line)
    }
}
