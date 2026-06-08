//
//  EffectSettingsSync.swift
//  SpectraWall
//
//  The keep-alive sync loop shared by every effect section: a @State `settings`
//  mirror kept in step with the type-erased `layer.effectSettings`. Previously
//  copy-pasted as four modifiers (onAppear / onChange(layer.id) / onChange(settings)
//  / onReceive) in Spectrum, Orb and Border sections.
//

import Combine
import SwiftUI

extension View {
    /// Bind a section's `settings` mirror to `layer.effectSettings`: load on
    /// appear and on layer switch, write edits back (skipping no-op writes that
    /// would re-fire objectWillChange), and re-sync when the layer mutates from
    /// elsewhere. `onLayerChange` fires on layer switch — sections use it to clear
    /// transient state like the randomize-undo snapshot.
    func syncEffectSettings<S: EffectSettings & Equatable>(
        _ settings: Binding<S>,
        layer: LayerSettings,
        onLayerChange: @escaping () -> Void = {}
    ) -> some View {
        modifier(EffectSettingsSync(settings: settings, layer: layer, onLayerChange: onLayerChange))
    }
}

private struct EffectSettingsSync<S: EffectSettings & Equatable>: ViewModifier {
    @Binding var settings: S
    // Plain reference, not @ObservedObject — the enclosing section already
    // observes `layer`, so its re-renders re-evaluate this modifier (and thus
    // onChange(of: layer.id)); we only need the publisher for onReceive.
    let layer: LayerSettings
    let onLayerChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { load() }
            // Re-sync when this section is reused for a different layer (sections
            // drop `.id(layer.id)` to avoid expensive ColorPicker rebuilds).
            .onChange(of: layer.id) { _, _ in
                onLayerChange()
                load()
            }
            .onChange(of: settings) { _, newValue in
                // Skip write-back when the value already matches — avoids the
                // onAppear → onChange feedback loop firing layer.objectWillChange
                // on every layer switch.
                if let current = layer.effectSettings as? S, current == newValue { return }
                layer.effectSettings = newValue
                VisualizerSceneManager.shared.save()
            }
            .onReceive(layer.objectWillChange) { _ in
                if let latest = layer.effectSettings as? S, latest != settings {
                    settings = latest
                }
            }
    }

    private func load() {
        if let latest = layer.effectSettings as? S {
            settings = latest
        }
    }
}
