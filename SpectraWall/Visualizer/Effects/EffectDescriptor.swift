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

/// Which layer-level common controls (opacity / position / channel) the
/// settings panel should expose for an effect. Property still exists on
/// `LayerSettings` regardless — this just hides the slider when the effect
/// has no use for it (e.g. Border ignores positionX/Y because the trail
/// follows the screen edge).
struct CommonSettings: OptionSet {
    let rawValue: Int
    static let opacity     = CommonSettings(rawValue: 1 << 0)
    static let position    = CommonSettings(rawValue: 1 << 1) // x + y together
    static let channelMode = CommonSettings(rawValue: 1 << 2)
    static let all: CommonSettings = [.opacity, .position, .channelMode]
}

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

    /// Which layer-level common settings should be visible in the UI. Default
    /// `.all` keeps every slider; effects whose value of a particular setting
    /// is meaningless (e.g. Border + position) drop it from this set.
    let commonSettings: CommonSettings

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

    init(
        type: EffectType,
        displayName: LocalizedStringResource,
        iconAssetName: String,
        renderOrder: Int,
        commonSettings: CommonSettings = .all,
        makeDefaultSettings: @escaping () -> any EffectSettings,
        settingsCodec: EffectSettingsCodec,
        makeEffect: @escaping (_ size: CGSize, _ layer: LayerSettings, _ screen: NSScreen) -> (any Effect)?,
        makeSettingsView: @escaping (LayerSettings) -> AnyView,
        pipelineSpec: PipelineSpec
    ) {
        self.type = type
        self.displayName = displayName
        self.iconAssetName = iconAssetName
        self.renderOrder = renderOrder
        self.commonSettings = commonSettings
        self.makeDefaultSettings = makeDefaultSettings
        self.settingsCodec = settingsCodec
        self.makeEffect = makeEffect
        self.makeSettingsView = makeSettingsView
        self.pipelineSpec = pipelineSpec
    }
}
