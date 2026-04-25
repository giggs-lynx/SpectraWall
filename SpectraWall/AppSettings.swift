//
//  AppSettings.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/25.
//

import SwiftUI
import Combine

enum AudioSource: Equatable {
    case global
    case app(AudioApp)

    var displayName: String {
        switch self {
        case .global: return "Global（所有音訊）"
        case .app(let app): return app.name
        }
    }
}

extension AudioApp: Equatable {
    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.pid == rhs.pid
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @Published var audioSource: AudioSource = .global
    @Published var activeApps: [AudioApp] = []
    @Published var lastSelectedApp: AudioApp? = nil  // 加這個
}
