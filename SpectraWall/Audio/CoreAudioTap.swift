//
//  CoreAudioTap.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import AudioToolbox

class CoreAudioTap {
    var onAudioData: (([Float], [Float]) -> Void)?

    private var tapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var deviceReadyListenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Public/Users/giggs/project/lab/SpectraWall/SpectraWall/Audio/CoreAudioTap.swift

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
        // 1. 建立 Process Tap
        let tapUID = UUID()
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: app.objectIDs)
        tapDesc.uuid = tapUID
        tapDesc.muteBehavior = .unmuted

        var tapObjectID: AudioObjectID = .unknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &tapObjectID)
        guard tapStatus == noErr else {
            print("CoreAudioTap: 建立 tap 失敗，OSStatus = \(tapStatus)")
            return
        }
        tapID = tapObjectID
        print("CoreAudioTap: tap 建立成功，ID = \(tapObjectID)")

        // 2. 建立 Aggregate Device
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SpectraWallTap",
            kAudioAggregateDeviceUIDKey: "spectrawall-\(UUID().uuidString)",
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID.uuidString]],
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceIsPrivateKey: true
        ]

        var aggID: AudioObjectID = .unknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
        guard aggStatus == noErr else {
            print("CoreAudioTap: 建立 aggregate device 失敗，OSStatus = \(aggStatus)")
            return
        }
        aggregateDeviceID = aggID
        print("CoreAudioTap: aggregate device 建立成功，ID = \(aggID)")

        // 3. 等待 aggregate device 準備好
        waitForAggregateDevice(aggID) { [weak self] in
            guard let self else { return }
            print("CoreAudioTap: aggregate device 已就緒")
            self.startIOProc(deviceID: aggID, app: app)
        }
    }
    
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
            print("CoreAudioTap: 建立 global tap 失敗，OSStatus = \(tapStatus)")
            return
        }
        tapID = tapObjectID

        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SpectraWallGlobalTap",
            kAudioAggregateDeviceUIDKey: "spectrawall-global-\(UUID().uuidString)",
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID.uuidString]],
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceIsPrivateKey: true
        ]

        var aggID: AudioObjectID = .unknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggID)
        guard aggStatus == noErr else {
            print("CoreAudioTap: 建立 global aggregate device 失敗，OSStatus = \(aggStatus)")
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

        deviceReadyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            if let block = self.deviceReadyListenerBlock {
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
                self.deviceReadyListenerBlock = nil
            }
            completion()
        }

        AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, deviceReadyListenerBlock!)
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
        print("CoreAudioTap: sample rate = \(sampleRate)")
        
        var procID: AudioDeviceIOProcID?

        let err = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil) { [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            self.handleAudioBuffer(inInputData)
        }

        guard err == noErr, let procID else {
            print("CoreAudioTap: 建立 IO proc 失敗，OSStatus = \(err)")
            return
        }

        deviceProcID = procID

        let startErr = AudioDeviceStart(deviceID, procID)
        guard startErr == noErr else {
            print("CoreAudioTap: 啟動 device 失敗，OSStatus = \(startErr)")
            return
        }

        print("CoreAudioTap: 開始擷取 \(app.name)")
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
                // 交錯格式：L R L R L R...
                for i in 0..<frameCount {
                    leftSamples.append(samples[i * 2])
                    rightSamples.append(samples[i * 2 + 1])
                }
            } else {
                // 單聲道，左右都用同一個
                for i in 0..<frameCount {
                    leftSamples.append(samples[i])
                    rightSamples.append(samples[i])
                }
            }
        }

        guard !leftSamples.isEmpty else { return }

        DispatchQueue.main.async {
            self.onAudioData?(leftSamples, rightSamples)
        }
    }
}
