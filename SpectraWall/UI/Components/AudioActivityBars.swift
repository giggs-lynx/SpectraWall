//
//  AudioActivityBars.swift
//  SpectraWall
//
//  Small EQ-style meter for the popover: dancing bars when the selected source
//  is producing sound, collapsed/greyed when silent. Driven by AudioActivityMonitor.
//

import SwiftUI

struct AudioActivityBars: View {
    @ObservedObject private var monitor = AudioActivityMonitor.shared

    private let barWidth: CGFloat = 2.5
    private let spacing: CGFloat = 2
    private let maxHeight: CGFloat = 13
    private let minHeight: CGFloat = 2.5

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(monitor.bands.indices, id: \.self) { i in
                Capsule()
                    .fill(monitor.isSilent ? Color.secondary.opacity(0.35) : Color.accentColor)
                    .frame(width: barWidth, height: height(for: monitor.bands[i]))
            }
        }
        .frame(height: maxHeight)
        .help(monitor.isSilent ? "No audio detected" : "Receiving audio")
        .accessibilityLabel(monitor.isSilent ? "No audio detected" : "Receiving audio")
    }

    private func height(for value: Double) -> CGFloat {
        guard !monitor.isSilent else { return minHeight }
        return minHeight + (maxHeight - minHeight) * CGFloat(value)
    }
}
