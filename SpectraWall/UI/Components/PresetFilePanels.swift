//
//  PresetFilePanels.swift
//  SpectraWall
//
//  AppKit save/open panels for preset export/import. Deliberately not
//  SwiftUI fileExporter/fileImporter: those need FileDocument wrappers and
//  are flaky about coming to the foreground from an accessory-app Settings
//  scene, while a modal NSSavePanel is the proven path (app is unsandboxed,
//  so no entitlement concerns).
//

import AppKit
import UniformTypeIdentifiers

enum PresetFilePanels {

    /// Returns the chosen destination URL, or nil if the user cancelled.
    static func runSavePanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName + ".json"
        // Accessory app: without activation the panel can open behind other
        // windows.
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Returns the chosen file URL, or nil if the user cancelled.
    static func runOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
