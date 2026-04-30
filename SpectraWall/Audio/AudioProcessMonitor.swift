//
//  AudioProcessMonitor.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import AppKit
import AudioToolbox
import os

struct AudioApp {
    let pid: pid_t
    let objectIDs: [AudioObjectID]
    let name: String
    let bundleID: String?
}

class AudioProcessMonitor {
    var onAppsChanged: (([AudioApp]) -> Void)?
    private(set) var activeApps: [AudioApp] = []
    
    private let logger = Logger(subsystem: AppConstants.bundleId, category: "AudioProcessMonitor")
    
    private var processListListenerBlock: AudioObjectPropertyListenerBlock?
    private var processListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var monitoredProcesses: Set<AudioObjectID> = []
    private var periodicRefreshTask: Task<Void, Never>?
    
    private var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    // MARK: - Public
    
    func start() {
        guard processListListenerBlock == nil else { return }
        
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        
        processListListenerBlock = listener
        
        AudioObjectAddPropertyListenerBlock(
            .system,
            &processListAddress,
            .main,
            listener
        )
        
        refresh()
        startPeriodicRefresh()
    }
    
    func stop() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        
        if let block = processListListenerBlock {
            AudioObjectRemovePropertyListenerBlock(.system, &processListAddress, .main, block)
            processListListenerBlock = nil
        }
        
        removeAllProcessListeners()
        activeApps = []
    }
    
    // MARK: - Periodic Refresh
    
    private func startPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.refresh() }
            }
        }
    }
    
    // MARK: - Refresh
    
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
                
                result[pid] = AudioApp(
                    pid: existing.pid,
                    objectIDs: mergedIDs,
                    name: existing.name,
                    bundleID: existing.bundleID
                )
            } else {
                result[pid] = AudioApp(pid: pid, objectIDs: [objectID], name: name, bundleID: bundleID)
            }
        }
        
        // Add isRunning listeners for all processes (including those not currently playing audio)
        updateProcessListeners(for: processIDs)
        
        let sorted = result.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        
        let oldIDs = Set(activeApps.map { $0.pid })
        let newIDs = Set(sorted.map { $0.pid })
        
        activeApps = sorted
        if oldIDs != newIDs {
            onAppsChanged?(sorted)
        }
    }
    
    // MARK: - Process Listeners
    
    private func updateProcessListeners(for processIDs: [AudioObjectID]) {
        let currentSet = Set(processIDs)
        
        let removed = monitoredProcesses.subtracting(currentSet)
        removed.forEach { removeProcessListener(for: $0) }
        
        let added = currentSet.subtracting(monitoredProcesses)
        added.forEach { addProcessListener(for: $0) }
        
        monitoredProcesses = currentSet
    }
    
    private func addProcessListener(for objectID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block)
        if status == noErr {
            processListenerBlocks[objectID] = block
        }
    }
    
    private func removeProcessListener(for objectID: AudioObjectID) {
        guard let block = processListenerBlocks.removeValue(forKey: objectID) else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
        if status != noErr && status != OSStatus(kAudioHardwareBadObjectError) {
            logger.error("Failed to remove listener for \(objectID): \(status)")
        }
    }
    
    private func removeAllProcessListeners() {
        monitoredProcesses.forEach { removeProcessListener(for: $0) }
        monitoredProcesses.removeAll()
        processListenerBlocks.removeAll()
    }
}
