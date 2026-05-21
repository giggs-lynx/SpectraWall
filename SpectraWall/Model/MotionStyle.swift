//
//  MotionStyle.swift
//  SpectraWall
//
//  Animation lerp choice shared by Orb and Spectrum effects.
//  - .snappy:  linear tween over a fixed duration — matches old SpriteKit
//              SKAction.scale/resize behavior (50ms reaches target). Sharper,
//              tighter motion; L/R orbs visually sync more crisply.
//  - .smooth:  exponential approach with a 50ms time constant. Softer, more
//              dampened feel with a "tail" after each audio event.
//

import Foundation

enum MotionStyle: String, Codable, CaseIterable {
    case snappy
    case smooth

    var localized: LocalizedStringResource {
        switch self {
        case .snappy: return "Snappy"
        case .smooth: return "Smooth"
        }
    }

    var caption: LocalizedStringResource {
        switch self {
        case .snappy: return "Sharp linear tween; tight L/R sync"
        case .smooth: return "Soft exponential approach; gentle tail"
        }
    }
}
