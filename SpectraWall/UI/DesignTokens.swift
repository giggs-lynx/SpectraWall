//
//  DesignTokens.swift
//  SpectraWall
//
//  Central UI constants so spacing / corner radius / hover treatment stay
//  consistent across the popover and settings panels instead of being
//  re-typed as magic numbers per call site.
//

import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

enum Radius {
    /// Hover/selection highlight behind list rows.
    static let row: CGFloat = 6
}

enum Hover {
    /// Standard background tint for a hovered, tappable row.
    static let fill = Color.primary.opacity(0.08)
}
