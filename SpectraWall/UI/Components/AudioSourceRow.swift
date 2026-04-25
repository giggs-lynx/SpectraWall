//
//  AudioSourceRow.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI

struct AudioSourceRow: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDisabled ? .secondary : (isSelected ? .accentColor : .secondary))
                    .frame(width: 16)
                Text(title)
                    .foregroundColor(isDisabled ? .secondary : .primary)
                Spacer()
                if isDisabled {
                    Text("無音訊")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
