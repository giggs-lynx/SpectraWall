//
//  AudioSourceRow.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI

struct AudioSourceRow: View {
    // MARK: - Properties
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    // MARK: - Computed Properties (Styles)
    private var iconColor: Color {
        if isDisabled { return .secondary }
        return isSelected ? .accentColor : .secondary
    }

    private var textColor: Color {
        isDisabled ? .secondary : .primary
    }

    // MARK: - Body
    var body: some View {
        Button(action: action) {
            rowContent
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(backgroundView)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Subviews
    private var rowContent: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(iconColor)
                .frame(width: 16)
            
            Text(title)
                .foregroundColor(textColor)
            
            Spacer()
            
            if isDisabled {
                inactiveLabel
            }
        }
    }

    private var inactiveLabel: some View {
        Text("Inactive")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
    }
}
