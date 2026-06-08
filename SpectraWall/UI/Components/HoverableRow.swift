//
//  HoverableRow.swift
//  SpectraWall
//
//  One place for the "row that highlights on hover and fires on tap" pattern
//  that the popover repeated for scenes / settings / quit. Each call site
//  supplies its own content; the hover state, highlight, and hit area live here.
//

import SwiftUI

struct HoverableRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        content()
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.row)
                    .fill(isHovered ? Hover.fill : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { isHovered = $0 }
    }
}
