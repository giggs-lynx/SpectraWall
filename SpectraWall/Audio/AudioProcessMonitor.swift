//
//  AudioProcessMonitor.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import AppKit
import AudioToolbox

struct AudioApp {
    let pid: pid_t
    let objectIDs: [AudioObjectID]
    let name: String
    let bundleID: String?
}

class AudioProcessMonitor {
    var onAppsChanged: (([AudioApp]) -> Void)?
    private(set) var activeApps: [AudioApp] = []

    private var processListListenerBlock: AudioObjectPropertyListenerBlock?
    private var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // MARK: - Public

    func start() {
        guard processListListenerBlock == nil else { return }

        processListListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }

        AudioObjectAddPropertyListenerBlock(
            .system,
            &processListAddress,
            .main,
            processListListenerBlock!
        )

        refresh()
    }

    func stop() {
        if let block = processListListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &processListAddress, .main, block)
            processListListenerBlock = nil
        }
        activeApps = []
    }

    // MARK: - Private

    private func refresh() {
        guard let processIDs = try? AudioObjectID.readProcessList() else { return }

        let runningApps = NSWorkspace.shared.runningApplications
        let appsByPID = Dictionary(runningApps.map { ($0.processIdentifier, $0) },
                                   uniquingKeysWith: { _, latest in latest })
        let myPID = ProcessInfo.processInfo.processIdentifier

        var result: [pid_t: AudioApp] = [:]

        for objectID in processIDs {
            guard let pid = try? objectID.readProcessPID(),
                  pid != myPID,
                  objectID.readProcessIsRunning() else { continue }

            let runningApp = appsByPID[pid]
            let name = runningApp?.localizedName
                ?? objectID.readProcessBundleID()?.components(separatedBy: ".").last
                ?? "Unknown"
            let bundleID = runningApp?.bundleIdentifier ?? objectID.readProcessBundleID()

            if let existing = result[pid] {
                var mergedIDs = existing.objectIDs
                if !mergedIDs.contains(objectID) { mergedIDs.append(objectID) }
                result[pid] = AudioApp(pid: existing.pid, objectIDs: mergedIDs, name: existing.name, bundleID: existing.bundleID)
            } else {
                result[pid] = AudioApp(pid: pid, objectIDs: [objectID], name: name, bundleID: bundleID)
            }
        }

        let sorted = result.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        activeApps = sorted
        onAppsChanged?(sorted)
    }
}
