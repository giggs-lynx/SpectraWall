//
//  PresetStoreTests.swift
//  SpectraWallTests
//
//  Covers the preset snapshot/instantiate round trip and import validation.
//  Import validation must run AFTER decode: EffectType decodes any string
//  successfully and LayerSettings silently falls back to Spectrum defaults
//  for unknown types, so decodeImport has to scan the registry itself —
//  these tests pin that trap down.
//

import XCTest
@testable import SpectraWall

final class PresetStoreTests: XCTestCase {

    override static func setUp() {
        super.setUp()
        EffectRegistry.bootstrap()
    }

    private func makeScene(name: String = "Studio") -> SceneSettings {
        let scene = SceneSettings(name: name)
        let spectrum = LayerSettings(effectType: .spectrum)
        spectrum.opacity = 0.7
        let orb = LayerSettings(effectType: .orb)
        orb.positionX = 0.25
        let border = LayerSettings(effectType: .border)
        border.channelMode = .left
        scene.layers = [spectrum, orb, border]
        return scene
    }

    // MARK: - Snapshot round trip

    func testSnapshotMatchesSourceSceneByteForByte() throws {
        let scene = makeScene()
        let data = try XDGStorage.encodeJSONForDisk(scene)
        let snapshot = try JSONDecoder().decode(SceneSettings.self, from: data)

        // Content identical: re-encoding the snapshot reproduces the bytes.
        let reencoded = try XDGStorage.encodeJSONForDisk(snapshot)
        XCTAssertEqual(reencoded, data)

        // Identity independent: every layer got a fresh UUID, name untouched
        // (no " Copy" suffix from the copying init).
        XCTAssertEqual(snapshot.name, scene.name)
        XCTAssertEqual(snapshot.layers.count, scene.layers.count)
        let originalIDs = Set(scene.layers.map(\.id))
        for layer in snapshot.layers {
            XCTAssertFalse(originalIDs.contains(layer.id))
        }
    }

    func testEncodeJSONForDiskRoundsDoubles() throws {
        let scene = SceneSettings(name: "Rounding")
        let layer = LayerSettings(effectType: .spectrum)
        layer.opacity = 0.1 + 0.05   // 0.15000000000000002 without the rounding pass
        scene.layers = [layer]

        let text = try XCTUnwrap(String(data: XDGStorage.encodeJSONForDisk(scene), encoding: .utf8))
        XCTAssertTrue(text.contains("0.15"))
        XCTAssertFalse(text.contains("0.15000"))
    }

    // MARK: - Import validation

    func testDecodeImportAcceptsValidScene() throws {
        let data = try XDGStorage.encodeJSONForDisk(makeScene())
        let scene = try PresetStore.decodeImport(data)
        XCTAssertEqual(scene.layers.count, 3)
    }

    func testDecodeImportRejectsGarbage() {
        XCTAssertThrowsError(try PresetStore.decodeImport(Data("not json".utf8))) { error in
            guard case PresetImportError.malformed = error else {
                return XCTFail("Expected .malformed, got \(error)")
            }
        }
    }

    func testDecodeImportRejectsNewerVersion() throws {
        var json = try jsonObject(for: makeScene())
        json["version"] = 99
        let data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try PresetStore.decodeImport(data)) { error in
            guard case PresetImportError.unsupportedVersion(let found) = error else {
                return XCTFail("Expected .unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(found, 99)
        }
    }

    func testDecodeImportRejectsUnknownEffectType() throws {
        var json = try jsonObject(for: makeScene())
        guard var layers = json["layers"] as? [[String: Any]] else {
            return XCTFail("Encoded scene has no layers array")
        }
        layers[1]["effectType"] = "Hologram"
        json["layers"] = layers
        let data = try JSONSerialization.data(withJSONObject: json)

        // Sanity: plain decode succeeds (silent Spectrum fallback) — only
        // decodeImport's registry scan catches the unknown type.
        XCTAssertNoThrow(try JSONDecoder().decode(SceneSettings.self, from: data))
        XCTAssertThrowsError(try PresetStore.decodeImport(data)) { error in
            guard case PresetImportError.unknownEffectType(let raw) = error else {
                return XCTFail("Expected .unknownEffectType, got \(error)")
            }
            XCTAssertEqual(raw, "Hologram")
        }
    }

    private func jsonObject(for scene: SceneSettings) throws -> [String: Any] {
        let data = try XDGStorage.encodeJSONForDisk(scene)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
