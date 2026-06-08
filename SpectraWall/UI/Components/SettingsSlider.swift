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
    var unit: String? = nil

    /// Show as many decimals as the step implies: integer steps read as
    /// whole numbers (no more "12.00" for a step-1 slider), 0.1 → one place,
    /// finer → two.
    private var decimals: Int {
        if step >= 1 { return 0 }
        if step >= 0.1 { return 1 }
        return 2
    }

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
        let formatted = String(format: "%.\(decimals)f", value)
        return Text(unit.map { "\(formatted) \($0)" } ?? formatted)
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()
            .frame(minWidth: 36, alignment: .trailing)
    }
}
