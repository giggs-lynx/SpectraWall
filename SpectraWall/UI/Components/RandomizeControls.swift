//
//  RandomizeControls.swift
//  SpectraWall
//
//  Dice + one-step Undo, shown as a SettingsCard accessory on each effect card.
//  Undo only appears while a pre-randomize snapshot is live.
//

import SwiftUI

struct RandomizeControls: View {
    let canUndo: Bool
    let onRandomize: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if canUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Undo randomize")
            }
            Button(action: onRandomize) {
                Image(systemName: "dice.fill")
            }
            .buttonStyle(.borderless)
            .help("Randomize settings")
        }
        .font(.subheadline)
    }
}
