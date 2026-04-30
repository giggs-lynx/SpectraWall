//
//  ColorPickerRow.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

struct ColorPickerRow: View {
    let label: LocalizedStringKey
    @Binding var colorData: ColorData

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            colorPicker
        }
        .frame(height: 24)
    }

    // MARK: - Subviews

    private var colorPicker: some View {
        ColorPicker("", selection: colorBinding)
            .labelsHidden()
            .fixedSize()
    }

    // MARK: - Helpers

    private var colorBinding: Binding<Color> {
        Binding(
            get: { colorData.color },
            set: { updateColor($0) }
        )
    }

    private func updateColor(_ newColor: Color) {
        if let nsColor = NSColor(newColor).usingColorSpace(.deviceRGB) {
            colorData = ColorData(nsColor)
        }
    }
}
