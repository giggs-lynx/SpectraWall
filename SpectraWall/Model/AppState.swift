//
//  AppState.swift
//  SpectraWall
//
//  Top-level Codable type written to ~/.local/state/spectrawall/state.json.
//  Internal machine-state that shouldn't be dotfile-tracked: which scene the
//  user had active last time, first-launch init sentinel, etc.
//

import Foundation

struct AppState: Codable {
    var version: Int = 1
    var enabledDisplayIDsInitialized: Bool = false
}
