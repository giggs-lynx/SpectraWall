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
    var unit: String?
    /// Double-click the value to snap back here. nil for sliders with no spec.
    var defaultValue: Double?

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var fieldFocused: Bool

    // MARK: - Init

    /// Explicit range/step — used by the 4 non-effect sliders (opacity, position,
    /// bass attenuation) that don't have a SliderSpec.
    init(
        label: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String? = nil,
        defaultValue: Double? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.defaultValue = defaultValue
    }

    /// Spec-driven — carries range/step/default from a single source of truth.
    init(label: LocalizedStringKey, value: Binding<Double>, spec: SliderSpec, unit: String? = nil) {
        self.label = label
        self._value = value
        self.range = spec.range
        self.step = spec.step
        self.unit = unit
        self.defaultValue = spec.defaultValue
    }

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

            if isEditing {
                editField
            } else {
                valueLabel
            }
        }
    }

    private var valueLabel: some View {
        let formatted = String(format: "%.\(decimals)f", value)
        // count:2 must be declared before count:1 so the double-click reset
        // isn't swallowed by the single-click edit gesture.
        return Text(unit.map { "\(formatted) \($0)" } ?? formatted)
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()
            .frame(minWidth: 36, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { resetToDefault() }
            .onTapGesture(count: 1) { beginEditing() }
            .help("Click to type a value, double-click to reset")
    }

    private var editField: some View {
        TextField("", text: $editText)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 56)
            .focused($fieldFocused)
            .onSubmit { commitEdit() }
            .onExitCommand { cancelEdit() }
            .onChange(of: fieldFocused) { _, focused in
                if !focused { commitEdit() }
            }
    }

    // MARK: - Actions

    private func resetToDefault() {
        guard let defaultValue else { return }
        value = SliderSpec.snap(defaultValue, range: range, step: step)
    }

    private func beginEditing() {
        editText = String(format: "%.\(decimals)f", value)
        isEditing = true
        fieldFocused = true
    }

    private func commitEdit() {
        guard isEditing else { return }
        isEditing = false
        // Invalid input reverts by leaving `value` untouched.
        if let raw = Double(editText.trimmingCharacters(in: .whitespaces)) {
            value = SliderSpec.snap(raw, range: range, step: step)
        }
    }

    private func cancelEdit() {
        isEditing = false
    }
}
