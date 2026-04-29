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
                .frame(width: 1200, height: 560)
                .navigationTitle("SpectraWall 設定")
        }
    }
}
