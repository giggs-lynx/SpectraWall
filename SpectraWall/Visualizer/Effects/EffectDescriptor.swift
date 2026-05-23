//
//  EffectDescriptor.swift
//  SpectraWall
//
//  Per-effect plug-in record. One descriptor per EffectType collects everything
//  EffectsCoordinator, EffectRenderer, LayerSettings's Codable, and the UI
//  need to know about a kind of effect. Adding a new effect = writing the
//  subclass + a static descriptor + EffectRegistry.register(...).
//

import SwiftUI

struct EffectDescriptor {
    let type: EffectType

    /// User-facing label (settings menus, popover lists).
    let displayName: LocalizedStringResource

    /// Asset catalog name for the effect's icon.
    let iconAssetName: String

    /// Back-to-front paint order in the renderer. Lower values are drawn
    /// first (further back); ties pick whichever happens to come out of the
    /// dict iteration order, so callers should use distinct values when
    /// layering matters.
    let renderOrder: Int

    /// Construct a default settings struct (used when adding a new layer or
    /// resetting an existing one).
    let makeDefaultSettings: () -> any EffectSettings

    /// Encode / decode the effect's settings struct as `any EffectSettings`.
    let settingsCodec: EffectSettingsCodec

    /// Build a concrete effect instance for a layer on a specific screen.
    let makeEffect: (_ size: CGSize, _ layer: LayerSettings, _ screen: NSScreen) -> (any Effect)?

    /// Build the SwiftUI settings panel for a layer of this type.
    let makeSettingsView: (LayerSettings) -> AnyView

    /// Metal pipeline declaration; the renderer compiles it during init.
    let pipelineSpec: PipelineSpec
}
