//
//  ColorPickerRow.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/27.
//

import SwiftUI

struct ColorPickerRow: View {
    let label: String
    @Binding var colorData: ColorData

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { colorData.color },
                set: { newColor in
                    if let nsColor = NSColor(newColor).usingColorSpace(.deviceRGB) {
                        colorData = ColorData(nsColor)
                    }
                }
            ))
            .labelsHidden()
        }
    }
}
