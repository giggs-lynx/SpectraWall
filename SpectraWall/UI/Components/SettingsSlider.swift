//
//  SettingsSlider.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI

struct SettingsSlider: View {
    // MARK: - Properties
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerView
            
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
        }
    }

    // MARK: - Subviews
    private var headerView: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            valueLabel
        }
    }

    private var valueLabel: some View {
        Text(String(format: "%.2f", value))
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()
            .frame(minWidth: 36, alignment: .trailing)
    }
}
