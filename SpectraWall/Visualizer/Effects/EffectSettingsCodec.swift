//
//  EffectSettingsCodec.swift
//  SpectraWall
//
//  Type-erased Codable bridge so EffectDescriptor can hold encode/decode
//  closures without exposing a generic constraint to LayerSettings (which
//  needs to store `any EffectSettings`). The factory captures the concrete
//  type once; runtime calls dispatch through closures.
//

import Foundation

struct EffectSettingsCodec {
    let decode: (Decoder) throws -> any EffectSettings
    let encode: (any EffectSettings, Encoder) throws -> Void

    /// Build a codec for a concrete EffectSettings type.
    static func make<T: EffectSettings>(_: T.Type) -> EffectSettingsCodec {
        EffectSettingsCodec(
            decode: { decoder in try T(from: decoder) },
            encode: { value, encoder in
                guard let typed = value as? T else {
                    throw EncodingError.invalidValue(
                        value,
                        EncodingError.Context(
                            codingPath: encoder.codingPath,
                            debugDescription:
                                "Expected \(T.self) but got \(type(of: value))"
                        )
                    )
                }
                try typed.encode(to: encoder)
            }
        )
    }
}
