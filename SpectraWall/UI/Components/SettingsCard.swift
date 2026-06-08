//
//  SettingsCard.swift
//  SpectraWall
//
//  Faux grouped-Form card. GlobalSettings uses a native `.formStyle(.grouped)`
//  Form, but the layer/effect panels can't: they rely on a keep-alive trick
//  (height-0 collapse of non-active effect sections) that breaks Form's Section
//  rendering. This container reproduces the grouped look as plain views so the
//  collapse keeps working while the panels still read as cards.
//

import SwiftUI

struct SettingsCard<Content: View, Accessory: View>: View {
    var title: LocalizedStringKey? = nil
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    // Default accessory closure lets the compiler infer Accessory = EmptyView at
    // call sites that don't pass one, so existing cards stay source-compatible.
    init(
        title: LocalizedStringKey? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let title {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, Spacing.xs)
                    Spacer()
                    accessory()
                }
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                content()
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        // Own bottom margin so the parent VStack can stay spacing-0 — that's what
        // lets height-0 inactive sections collapse without leaving phantom gaps.
        .padding(.bottom, Spacing.lg)
    }
}
