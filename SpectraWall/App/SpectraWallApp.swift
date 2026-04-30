//
//  SpectraWallApp.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SwiftUI

@main
struct SpectraWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsWindowView()
                .navigationTitle(AppConstants.appName)
        }
    }
}
