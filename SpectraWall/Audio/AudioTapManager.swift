//
//  AudioTapManager.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import AudioToolbox
import OSLog

class AudioTapManager {
    var onAudioData: (([Float], [Float]) -> Void)?

    private var tapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var deviceReadyListenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Public

    // Without this, ARC releasing an AudioTapManager instance leaves its
    // CATapDescription / aggregate device / IOProc alive in Core Audio.
    // AudioEngine.setupTap reassigns `tapManager = tap` without calling stop
    // on the previous instance, so every reassignment used to leak one tap.
    // The leaked taps stay registered with TCC, which re-prompts the user
    // on every wake — 5+ permission dialogs in a row was the visible symptom.
    deinit {
        stop()
    }

    func start(app: AudioApp) {
        stop()
        setupTap(app: app)
    }

    func stop() {
        if aggregateDeviceID.isValid, let procID = deviceProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        }
        deviceProcID = nil

        if aggregateDeviceID.isValid {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }

        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    // MARK: - Tap Setup

    private func setupTap(app: AudioApp) {
        // 1. Create Process Tap
        let tapUID = UUID()
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: app.objectIDs)
        tapDesc.uuid = tapUID
        tapDesc.muteBehavior = .unmuted

        var tapObjectID: AudioObjectID = .unknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tapObjectID)
        guard tapStatus == noErr else {
            AppLog.audio.error("Failed to create tap, OSStatus = \(tapStatus)")
            return
        }
        tapID = tapObjectID

        // 2. Create Aggregate Device
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "\(AppConstants.appName)Tap",
            kAudioAggregateDeviceUIDKey: "\(AppConstants.bundleId)-\(UUID().uuidString)",
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID.uuidString]],
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceIsPrivateKey: true
        ]

        var aggID: AudioObjectID = .unknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
        guard aggStatus == noErr else {
            AppLog.audio.error("Failed to create aggregate device, OSStatus = \(aggStatus)")
            return
        }
        aggregateDeviceID = aggID

        // 3. Wait for aggregate device to be ready
        waitForAggregateDevice(aggID) { [weak self] in
            guard let self else { return }
            self.startIOProc(deviceID: aggID, app: app)
        }
    }
    
    // MARK: - Global Tap
    
    func startGlobal() {
        stop()
        setupGlobalTap()
    }

    private func setupGlobalTap() {
        let tapUID = UUID()
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.uuid = tapUID
        tapDesc.muteBehavior = .unmuted
        
        var tapObjectID: AudioObjectID = .unknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tapObjectID)
        guard tapStatus == noErr else {
            AppLog.audio.error("Failed to create global tap, OSStatus = \(tapStatus)")
            return
        }
        tapID = tapObjectID
        
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "\(AppConstants.appName)GlobalTap",
            kAudioAggregateDeviceUIDKey: "\(AppConstants.bundleId)-global-\(UUID().uuidString)",
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID.uuidString]],
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceIsPrivateKey: true
        ]
        
        var aggID: AudioObjectID = .unknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
        guard aggStatus == noErr else {
            AppLog.audio.error("Failed to create global aggregate device, OSStatus = \(aggStatus)")
            return
        }
        aggregateDeviceID = aggID
        
        waitForAggregateDevice(aggID) { [weak self] in
            guard let self else { return }
            self.startIOProc(deviceID: aggID, app: AudioApp(pid: 0, objectIDs: [], name: "Global", bundleID: nil))
        }
    }

    // MARK: - Device Ready Listener

    private func waitForAggregateDevice(_ deviceID: AudioObjectID, completion: @escaping () -> Void) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isAlive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isAlive)
        if err == noErr && isAlive != 0 {
            completion()
            return
        }

        let listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            if let block = self.deviceReadyListenerBlock {
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
                self.deviceReadyListenerBlock = nil
            }
            completion()
        }

        self.deviceReadyListenerBlock = listenerBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, listenerBlock)
    }

    // MARK: - IO Proc
    
    private func startIOProc(deviceID: AudioObjectID, app: AudioApp) {
        
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        
        var procID: AudioDeviceIOProcID?
        
        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil) { [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            self.handleAudioBuffer(inInputData)
        }
        
        guard err == noErr, let procID else {
            AppLog.audio.error("Failed to create IO proc, OSStatus = \(err)")
            return
        }
        
        deviceProcID = procID
        
        let startErr = AudioDeviceStart(deviceID, procID)
        guard startErr == noErr else {
            AppLog.audio.error("Failed to start device, OSStatus = \(startErr)")
            return
        }
    }

    // MARK: - Audio Buffer Handler

    private func handleAudioBuffer(_ inputBufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBufferList))

        var leftSamples: [Float] = []
        var rightSamples: [Float] = []

        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let channelCount = Int(buffer.mNumberChannels)
            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / max(channelCount, 1)
            let samples = data.bindMemory(to: Float.self, capacity: frameCount * channelCount)

            if channelCount >= 2 {
                // Interleaved format: L R L R L R...
                for i in 0..<frameCount {
                    leftSamples.append(samples[i * 2])
                    rightSamples.append(samples[i * 2 + 1])
                }
            } else {
                // Mono channel, use same data for both channels
                for i in 0..<frameCount {
                    leftSamples.append(samples[i])
                    rightSamples.append(samples[i])
                }
            }
        }

        guard !leftSamples.isEmpty else { return }

        // Invoke directly on the audio thread. Subscribers use .receive(on: DispatchQueue.main)
        // to hop back to main as needed; removing this dispatch saves N·3-effect main-queue
        // blocks per audio buffer on multi-screen setups.
        self.onAudioData?(leftSamples, rightSamples)
    }
}
