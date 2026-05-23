//
//  AppLog.swift
//  SpectraWall
//
//  Central log namespace. All Logger instances live here so categories stay
//  consistent and call sites read uniformly. Use info-level for lifecycle
//  events — OSLog is zero-cost when no subscriber is attached, no compile
//  flag needed.
//
//  Inspect with:
//    log show --predicate 'subsystem == "com.spectrawall.app"' --info --last 5m
//

import OSLog

enum AppLog {
    static let lifecycle = Logger(subsystem: AppConstants.bundleId, category: "Lifecycle")
    static let render    = Logger(subsystem: AppConstants.bundleId, category: "Render")
    static let audio     = Logger(subsystem: AppConstants.bundleId, category: "Audio")
    static let analyzer  = Logger(subsystem: AppConstants.bundleId, category: "Analyzer")
    static let persist   = Logger(subsystem: AppConstants.bundleId, category: "Persist")
    static let scene     = Logger(subsystem: AppConstants.bundleId, category: "Scene")
    static let effect    = Logger(subsystem: AppConstants.bundleId, category: "Effect")
}
