import Accelerate
import AppKit
import CoreAudio
import Foundation
import Observation
import Synchronization
import UniformTypeIdentifiers

struct AudioAppSession: Identifiable, Equatable, Sendable {
    let id: String
    let pid: pid_t
    let processObjectIDs: [AudioObjectID]
    let name: String
    let bundleID: String
    let isRunningOutput: Bool
    let isRunningInput: Bool
    var volume: Float
    var isMuted: Bool

    static func == (lhs: AudioAppSession, rhs: AudioAppSession) -> Bool {
        lhs.id == rhs.id &&
        lhs.pid == rhs.pid &&
        lhs.processObjectIDs == rhs.processObjectIDs &&
        lhs.name == rhs.name &&
        lhs.bundleID == rhs.bundleID &&
        lhs.isRunningOutput == rhs.isRunningOutput &&
        lhs.isRunningInput == rhs.isRunningInput &&
        abs(lhs.volume - rhs.volume) < 0.001 &&
        lhs.isMuted == rhs.isMuted
    }
}

nonisolated func audioProcessListListenerProc(
    _ inObjectID: AudioObjectID,
    _ inNumberAddresses: UInt32,
    _ inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            AudioProcessVolumeManager.shared.scheduleRefreshProcesses()
        }
    }
    return noErr
}

nonisolated final class ProcessTapGainState: @unchecked Sendable {
    private let packedEffectiveGain = Atomic<UInt32>(Float(1.0).bitPattern)

    func update(gain: Float, muted: Bool) {
        let clamped = max(0.0, min(2.0, gain))
        let effective: Float = muted ? 0.0 : clamped
        packedEffectiveGain.store(effective.bitPattern, ordering: .relaxed)
    }

    func currentEffectiveGain() -> Float {
        let bits = packedEffectiveGain.load(ordering: .relaxed)
        return Float(bitPattern: bits)
    }
}

nonisolated final class ActiveProcessAudioTap: @unchecked Sendable {
    let appKey: String
    let processObjectIDs: [AudioObjectID]
    let gainState = ProcessTapGainState()
    private(set) var tapObjectID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private(set) var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private(set) var currentOutputDeviceUID: String?
    private var ioProcID: AudioDeviceIOProcID?

    init(appKey: String, processObjectIDs: [AudioObjectID]) {
        self.appKey = appKey
        self.processObjectIDs = processObjectIDs
    }

    func configure(volume: Float, isMuted: Bool, outputDeviceUID: String?) -> Bool {
        gainState.update(gain: volume, muted: isMuted)

        let needsSilenceOnly = isMuted || volume <= 0.001
        let needsGainScaling = !needsSilenceOnly && abs(volume - 1.0) > 0.01

        guard needsSilenceOnly || needsGainScaling else {
            teardown()
            return true
        }

        if needsSilenceOnly {
            if aggregateDeviceID != kAudioObjectUnknown {
                teardown()
            }
            if tapObjectID == kAudioObjectUnknown {
                return createMuteOnlyTap()
            }
            return true
        }

        if needsGainScaling {
            if aggregateDeviceID == kAudioObjectUnknown || currentOutputDeviceUID != outputDeviceUID {
                teardown()
                return createGainScalingTap(outputDeviceUID: outputDeviceUID)
            }
            return true
        }

        return true
    }

    private func createMuteOnlyTap() -> Bool {
        let desc = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        desc.name = "MonoHub Mute Tap (\(appKey))"
        desc.isPrivate = true
        desc.muteBehavior = .muted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard status == noErr, newTapID != kAudioObjectUnknown else {
            return false
        }
        self.tapObjectID = newTapID
        return true
    }

    private func createGainScalingTap(outputDeviceUID: String?) -> Bool {
        guard let outUID = outputDeviceUID, !outUID.isEmpty else {
            return false
        }

        let desc = CATapDescription(processes: processObjectIDs, deviceUID: outUID, stream: 0)
        let tapUUID = UUID()
        desc.uuid = tapUUID
        desc.name = "MonoHub Volume Tap (\(appKey))"
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard tapStatus == noErr, newTapID != kAudioObjectUnknown else {
            return false
        }
        self.tapObjectID = newTapID

        let aggUID = "com.monohub.agg.\(UUID().uuidString)"
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "MonoHub Mixer (\(appKey))",
            kAudioAggregateDeviceUIDKey as String: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey as String: outUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [
                    kAudioSubDeviceUIDKey as String: outUID,
                    kAudioSubDeviceInputChannelsKey as String: 0,
                    kAudioSubDeviceDriftCompensationKey as String: false
                ]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey as String: true
                ]
            ]
        ]

        var newAggID = AudioObjectID(kAudioObjectUnknown)
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAggID)
        guard aggStatus == noErr, newAggID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(newTapID)
            self.tapObjectID = AudioObjectID(kAudioObjectUnknown)
            return false
        }
        self.aggregateDeviceID = newAggID

        let state = self.gainState
        var newIOProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newIOProcID,
            newAggID,
            nil
        ) { _, inInputData, _, outOutputData, _ in
            let gain = state.currentEffectiveGain()
            let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let outBuffers = UnsafeMutableAudioBufferListPointer(outOutputData)
            let outCount = outBuffers.count
            guard outCount > 0 else { return }

            let lastInChannels = inBuffers.last?.mNumberChannels ?? 0
            let outFirstChannels = outBuffers[0].mNumberChannels

            if let tapBuf = inBuffers.last,
               lastInChannels == 2,
               outCount >= 2,
               outFirstChannels == 1 {
                var outL = outBuffers[0]
                var outR = outBuffers[1]
                let inFrames = Int(tapBuf.mDataByteSize) / (2 * MemoryLayout<Float32>.size)
                let outLFrames = Int(outL.mDataByteSize) / MemoryLayout<Float32>.size
                let outRFrames = Int(outR.mDataByteSize) / MemoryLayout<Float32>.size
                let frameCount = min(inFrames, min(outLFrames, outRFrames))
                let outByteCount = frameCount * MemoryLayout<Float32>.size

                if frameCount > 0,
                   let inPtr = tapBuf.mData?.assumingMemoryBound(to: Float32.self),
                   let outLPtr = outL.mData?.assumingMemoryBound(to: Float32.self),
                   let outRPtr = outR.mData?.assumingMemoryBound(to: Float32.self) {
                    if gain <= 0.0001 {
                        memset(outLPtr, 0, outByteCount)
                        memset(outRPtr, 0, outByteCount)
                    } else {
                        var scalar = gain
                        var low: Float = -1.0
                        var high: Float = 1.0
                        vDSP_vsmul(inPtr, 2, &scalar, outLPtr, 1, vDSP_Length(frameCount))
                        vDSP_vsmul(inPtr.advanced(by: 1), 2, &scalar, outRPtr, 1, vDSP_Length(frameCount))
                        vDSP_vclip(outLPtr, 1, &low, &high, outLPtr, 1, vDSP_Length(frameCount))
                        vDSP_vclip(outRPtr, 1, &low, &high, outRPtr, 1, vDSP_Length(frameCount))
                    }
                    outL.mDataByteSize = UInt32(outByteCount)
                    outR.mDataByteSize = UInt32(outByteCount)
                    outBuffers[0] = outL
                    outBuffers[1] = outR
                } else {
                    if let ptrL = outL.mData, outL.mDataByteSize > 0 { memset(ptrL, 0, Int(outL.mDataByteSize)) }
                    if let ptrR = outR.mData, outR.mDataByteSize > 0 { memset(ptrR, 0, Int(outR.mDataByteSize)) }
                }

                if outCount > 2 {
                    for idx in 2..<outCount {
                        let extraOut = outBuffers[idx]
                        if let outData = extraOut.mData, extraOut.mDataByteSize > 0 {
                            memset(outData, 0, Int(extraOut.mDataByteSize))
                        }
                    }
                }
                return
            }

            if outCount == 1,
               outFirstChannels == 2,
               inBuffers.count >= 2,
               inBuffers[inBuffers.count - 2].mNumberChannels == 1,
               inBuffers[inBuffers.count - 1].mNumberChannels == 1 {
                let inL = inBuffers[inBuffers.count - 2]
                let inR = inBuffers[inBuffers.count - 1]
                var outBuf = outBuffers[0]
                let inLFrames = Int(inL.mDataByteSize) / MemoryLayout<Float32>.size
                let inRFrames = Int(inR.mDataByteSize) / MemoryLayout<Float32>.size
                let outFrames = Int(outBuf.mDataByteSize) / (2 * MemoryLayout<Float32>.size)
                let frameCount = min(min(inLFrames, inRFrames), outFrames)
                let outByteCount = frameCount * 2 * MemoryLayout<Float32>.size

                if frameCount > 0,
                   let inLPtr = inL.mData?.assumingMemoryBound(to: Float32.self),
                   let inRPtr = inR.mData?.assumingMemoryBound(to: Float32.self),
                   let outPtr = outBuf.mData?.assumingMemoryBound(to: Float32.self) {
                    if gain <= 0.0001 {
                        memset(outPtr, 0, outByteCount)
                    } else {
                        var scalar = gain
                        var low: Float = -1.0
                        var high: Float = 1.0
                        vDSP_vsmul(inLPtr, 1, &scalar, outPtr, 2, vDSP_Length(frameCount))
                        vDSP_vsmul(inRPtr, 1, &scalar, outPtr.advanced(by: 1), 2, vDSP_Length(frameCount))
                        vDSP_vclip(outPtr, 1, &low, &high, outPtr, 1, vDSP_Length(frameCount * 2))
                    }
                    outBuf.mDataByteSize = UInt32(outByteCount)
                    outBuffers[0] = outBuf
                } else if let outData = outBuf.mData, outBuf.mDataByteSize > 0 {
                    memset(outData, 0, Int(outBuf.mDataByteSize))
                }
                return
            }

            let tapStart = inBuffers.count >= outCount ? (inBuffers.count - outCount) : 0
            let count = min(inBuffers.count - tapStart, outCount)

            for idx in 0..<count {
                let inBuf = inBuffers[tapStart + idx]
                var outBuf = outBuffers[idx]
                let byteCount = min(Int(inBuf.mDataByteSize), Int(outBuf.mDataByteSize))
                guard byteCount > 0,
                      let inPtr = inBuf.mData?.assumingMemoryBound(to: Float32.self),
                      let outPtr = outBuf.mData?.assumingMemoryBound(to: Float32.self) else {
                    if let outData = outBuf.mData, outBuf.mDataByteSize > 0 {
                        memset(outData, 0, Int(outBuf.mDataByteSize))
                    }
                    continue
                }
                let sampleCount = byteCount / MemoryLayout<Float32>.size
                if gain <= 0.0001 {
                    memset(outPtr, 0, byteCount)
                } else if abs(gain - 1.0) <= 0.0001 {
                    memcpy(outPtr, inPtr, byteCount)
                } else if sampleCount > 0 {
                    var scalar = gain
                    var low: Float = -1.0
                    var high: Float = 1.0
                    vDSP_vsmul(inPtr, 1, &scalar, outPtr, 1, vDSP_Length(sampleCount))
                    vDSP_vclip(outPtr, 1, &low, &high, outPtr, 1, vDSP_Length(sampleCount))
                }
                outBuf.mDataByteSize = UInt32(byteCount)
                outBuffers[idx] = outBuf
            }

            if outCount > count {
                for idx in count..<outCount {
                    let outBuf = outBuffers[idx]
                    if let outData = outBuf.mData, outBuf.mDataByteSize > 0 {
                        memset(outData, 0, Int(outBuf.mDataByteSize))
                    }
                }
            }
        }

        guard ioStatus == noErr, let validIOProc = newIOProcID else {
            AudioHardwareDestroyAggregateDevice(newAggID)
            AudioHardwareDestroyProcessTap(newTapID)
            self.aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            self.tapObjectID = AudioObjectID(kAudioObjectUnknown)
            return false
        }
        self.ioProcID = validIOProc

        let startStatus = AudioDeviceStart(newAggID, validIOProc)
        if startStatus != noErr {
            AudioDeviceDestroyIOProcID(newAggID, validIOProc)
            AudioHardwareDestroyAggregateDevice(newAggID)
            AudioHardwareDestroyProcessTap(newTapID)
            self.ioProcID = nil
            self.aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            self.tapObjectID = AudioObjectID(kAudioObjectUnknown)
            return false
        }

        self.currentOutputDeviceUID = outUID
        return true
    }

    func teardown() {
        currentOutputDeviceUID = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateDeviceID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
                self.ioProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapObjectID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapObjectID)
            tapObjectID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit {
        teardown()
    }
}

@Observable
@MainActor
final class AudioProcessVolumeManager {
    static let shared = AudioProcessVolumeManager()

    private(set) var activeSessions: [AudioAppSession] = []
    private(set) var isMonitoring: Bool = false

    @ObservationIgnored private var monitoringClients: Set<String> = []
    @ObservationIgnored private var savedVolumes: [String: Float] = [:]
    @ObservationIgnored private var savedMuted: [String: Bool] = [:]
    @ObservationIgnored private var activeTaps: [String: ActiveProcessAudioTap] = [:]
    @ObservationIgnored private(set) var sessionTapOutputUIDs: [String: String] = [:]
    @ObservationIgnored private var appIconsCache: [String: NSImage] = [:]
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var pendingRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var isConfiguringTap = false
    @ObservationIgnored private var failedTapBackoffUntil: [String: Date] = [:]
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    private static let savedVolumesKey = "MonoHub_PerAppAudioVolumes"
    private static let savedMutedKey = "MonoHub_PerAppAudioMuted"
    private static let tapRetryBackoffSeconds: TimeInterval = 3.0

    private init() {
        let defaults = UserDefaults.standard
        if let dict = defaults.dictionary(forKey: Self.savedVolumesKey) as? [String: Double] {
            self.savedVolumes = dict.mapValues { Float($0) }
        }
        if let dict = defaults.dictionary(forKey: Self.savedMutedKey) as? [String: Bool] {
            self.savedMuted = dict
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AudioProcessVolumeManager.shared.teardownAllTaps()
            }
        }
    }

    func startMonitoring(client: String) {
        monitoringClients.insert(client)
        updateRefreshTimerState()
        guard !isMonitoring else {
            refreshProcesses()
            return
        }
        isMonitoring = true
        guard !AppInfo.isRunningTests else { return }

        var addr = Self.processObjectListAddress
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            audioProcessListListenerProc,
            nil
        )

        refreshProcesses()
    }

    func stopMonitoring(client: String) {
        monitoringClients.remove(client)
        updateRefreshTimerState()
        guard monitoringClients.isEmpty, isMonitoring else { return }
        isMonitoring = false
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil

        guard !AppInfo.isRunningTests else { return }
        var addr = Self.processObjectListAddress
        _ = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            audioProcessListListenerProc,
            nil
        )
    }

    func scheduleRefreshProcesses() {
        guard isMonitoring, !AppInfo.isRunningTests, !isConfiguringTap else { return }
        let hasActiveUIClient = monitoringClients.contains { $0 != "audioControlFeature" }
        let hasCustomSettings = !savedVolumes.isEmpty || !savedMuted.isEmpty || !activeTaps.isEmpty
        guard hasActiveUIClient || hasCustomSettings else { return }
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let self, self.isMonitoring else { return }
            self.pendingRefreshTask = nil
            self.refreshProcesses()
        }
    }

    private func updateRefreshTimerState() {
        let hasActiveUIClient = monitoringClients.contains { $0 != "audioControlFeature" }
        if hasActiveUIClient && !AppInfo.isRunningTests {
            guard refreshTimer == nil else { return }
            let timer = Timer(timeInterval: 2.0, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard !NotchWindowController.shared.isDisplayAsleep else { return }
                    AudioProcessVolumeManager.shared.refreshProcesses()
                }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    func icon(for session: AudioAppSession) -> NSImage {
        if let cached = appIconsCache[session.id] {
            return cached
        }
        if let running = NSRunningApplication(processIdentifier: session.pid),
           let icon = running.icon {
            appIconsCache[session.id] = icon
            return icon
        }
        if !session.bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: session.bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            appIconsCache[session.id] = icon
            return icon
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    func setVolume(_ volume: Float, for sessionID: String) {
        let clamped = max(0.0, min(1.5, volume))
        savedVolumes[sessionID] = clamped
        if clamped > 0.001, savedMuted[sessionID] == true {
            savedMuted[sessionID] = false
        }
        failedTapBackoffUntil.removeValue(forKey: sessionID)
        persistSettings()

        if let idx = activeSessions.firstIndex(where: { $0.id == sessionID }) {
            activeSessions[idx].volume = clamped
            if clamped > 0.001 && activeSessions[idx].isMuted {
                activeSessions[idx].isMuted = false
            }
            applyTap(for: activeSessions[idx])
        }
    }

    func toggleMute(for sessionID: String) {
        let currentMuted = savedMuted[sessionID] ?? activeSessions.first(where: { $0.id == sessionID })?.isMuted ?? false
        setMuted(!currentMuted, for: sessionID)
    }

    func setMuted(_ muted: Bool, for sessionID: String) {
        savedMuted[sessionID] = muted
        failedTapBackoffUntil.removeValue(forKey: sessionID)
        persistSettings()

        if let idx = activeSessions.firstIndex(where: { $0.id == sessionID }) {
            activeSessions[idx].isMuted = muted
            applyTap(for: activeSessions[idx])
        }
    }

    func resetAllToDefault() {
        savedVolumes.removeAll()
        savedMuted.removeAll()
        failedTapBackoffUntil.removeAll()
        persistSettings()
        teardownAllTaps()
        for idx in activeSessions.indices {
            activeSessions[idx].volume = 1.0
            activeSessions[idx].isMuted = false
        }
    }

    func teardownAllTaps() {
        isConfiguringTap = true
        defer { isConfiguringTap = false }
        for tap in activeTaps.values {
            tap.teardown()
        }
        activeTaps.removeAll()
        sessionTapOutputUIDs.removeAll()
        failedTapBackoffUntil.removeAll()
    }

    func handleOutputDeviceChanged(to newOutputUID: String?) {
        if let newOutputUID, !newOutputUID.isEmpty {
            failedTapBackoffUntil.removeAll()
        }
        for session in activeSessions {
            let needsTap = session.isMuted || (abs(session.volume - 1.0) > 0.01 && session.isRunningOutput)
            if activeTaps[session.id] != nil || sessionTapOutputUIDs[session.id] != nil || needsTap {
                applyTap(for: session, outputDeviceUID: newOutputUID)
            }
        }
    }

    private func persistSettings() {
        guard !AppInfo.isRunningTests else { return }
        let defaults = UserDefaults.standard
        defaults.set(savedVolumes.mapValues { Double($0) }, forKey: Self.savedVolumesKey)
        defaults.set(savedMuted, forKey: Self.savedMutedKey)
    }

    func refreshProcesses() {
        guard !AppInfo.isRunningTests, !isConfiguringTap else { return }
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil

        let processIDs = Self.allProcessObjectIDs()
        let myPID = ProcessInfo.processInfo.processIdentifier
        let appIndex = Self.indexRunningApplications(NSWorkspace.shared.runningApplications)
        let hasCustomSettings = !savedVolumes.isEmpty || !savedMuted.isEmpty || !activeTaps.isEmpty

        struct GroupedApp {
            var key: String
            var pid: pid_t
            var processObjectIDs: [AudioObjectID]
            var name: String
            var bundleID: String
            var isRunningOutput: Bool
            var isRunningInput: Bool
        }

        var grouped: [String: GroupedApp] = [:]

        for objID in processIDs {
            guard let pid = Self.getProcessPID(objID), pid > 0, pid != myPID else { continue }
            let isOutput = Self.getProcessFlag(objID, selector: kAudioProcessPropertyIsRunningOutput)
            let isInput = Self.getProcessFlag(objID, selector: kAudioProcessPropertyIsRunningInput)
            let isRunning = Self.getProcessFlag(objID, selector: kAudioProcessPropertyIsRunning)
            let isActiveAudio = isOutput || isInput || isRunning

            if !isActiveAudio && !hasCustomSettings {
                continue
            }

            let rawBundleID = Self.getProcessBundleID(objID)
            guard let resolvedApp = Self.resolveHostApplication(
                pid: pid,
                rawBundleID: rawBundleID,
                index: appIndex
            ), !resolvedApp.isTerminated else {
                continue
            }

            let bundleID = resolvedApp.bundleIdentifier ?? Self.normalizeBundleID(rawBundleID)
            let name = resolvedApp.localizedName
                ?? Self.fallbackAppName(from: bundleID, pid: pid)
            guard !name.isEmpty else { continue }

            let key = bundleID.isEmpty ? "pid-\(pid)" : bundleID
            let hasSavedAdjustment = (savedMuted[key] == true)
                || abs((savedVolumes[key] ?? 1.0) - 1.0) > 0.01
                || activeTaps[key] != nil
            guard isActiveAudio || hasSavedAdjustment else { continue }

            if var existing = grouped[key] {
                existing.processObjectIDs.append(objID)
                existing.isRunningOutput = existing.isRunningOutput || isOutput
                existing.isRunningInput = existing.isRunningInput || isInput
                grouped[key] = existing
            } else {
                grouped[key] = GroupedApp(
                    key: key,
                    pid: resolvedApp.processIdentifier > 0 ? resolvedApp.processIdentifier : pid,
                    processObjectIDs: [objID],
                    name: name,
                    bundleID: bundleID,
                    isRunningOutput: isOutput,
                    isRunningInput: isInput
                )
            }
        }

        let sortedSessions: [AudioAppSession] = grouped.values
            .sorted { lhs, rhs in
                if lhs.isRunningOutput != rhs.isRunningOutput {
                    return lhs.isRunningOutput && !rhs.isRunningOutput
                }
                if lhs.isRunningInput != rhs.isRunningInput {
                    return lhs.isRunningInput && !rhs.isRunningInput
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { item in
                let vol = savedVolumes[item.key] ?? 1.0
                let muted = savedMuted[item.key] ?? false
                return AudioAppSession(
                    id: item.key,
                    pid: item.pid,
                    processObjectIDs: Self.normalizedProcessObjectIDs(item.processObjectIDs),
                    name: item.name,
                    bundleID: item.bundleID,
                    isRunningOutput: item.isRunningOutput,
                    isRunningInput: item.isRunningInput,
                    volume: vol,
                    isMuted: muted
                )
            }

        if activeSessions != sortedSessions {
            activeSessions = sortedSessions
        }

        let activeKeys = Set(sortedSessions.map(\.id))
        if !activeTaps.isEmpty {
            isConfiguringTap = true
            for (key, tap) in activeTaps where !activeKeys.contains(key) {
                tap.teardown()
                activeTaps.removeValue(forKey: key)
                failedTapBackoffUntil.removeValue(forKey: key)
            }
            isConfiguringTap = false
        }
        for key in sessionTapOutputUIDs.keys where !activeKeys.contains(key) {
            sessionTapOutputUIDs.removeValue(forKey: key)
        }
        for key in appIconsCache.keys where !activeKeys.contains(key) && abs((savedVolumes[key] ?? 1.0) - 1.0) <= 0.01 && savedMuted[key] != true {
            appIconsCache.removeValue(forKey: key)
        }

        for session in sortedSessions {
            if session.isMuted || abs(session.volume - 1.0) > 0.01 {
                applyTap(for: session)
            }
        }
    }

    private func applyTap(for session: AudioAppSession, outputDeviceUID: String? = nil) {
        isConfiguringTap = true
        defer { isConfiguringTap = false }

        let needsTap = session.isMuted || (abs(session.volume - 1.0) > 0.01 && session.isRunningOutput)
        if !needsTap {
            failedTapBackoffUntil.removeValue(forKey: session.id)
            sessionTapOutputUIDs.removeValue(forKey: session.id)
            if let existing = activeTaps.removeValue(forKey: session.id) {
                existing.teardown()
            }
            return
        }

        let outUID = outputDeviceUID ?? AudioDeviceManager.shared.currentOutputDevice?.uid
        if let outUID, !outUID.isEmpty {
            sessionTapOutputUIDs[session.id] = outUID
        }

        guard !AppInfo.isRunningTests else { return }

        if let backoffUntil = failedTapBackoffUntil[session.id], Date() < backoffUntil {
            return
        }

        let tap: ActiveProcessAudioTap
        if let existing = activeTaps[session.id], existing.processObjectIDs == session.processObjectIDs {
            tap = existing
        } else {
            activeTaps[session.id]?.teardown()
            tap = ActiveProcessAudioTap(appKey: session.id, processObjectIDs: session.processObjectIDs)
            activeTaps[session.id] = tap
        }

        let configured = tap.configure(volume: session.volume, isMuted: session.isMuted, outputDeviceUID: outUID)
        if configured {
            failedTapBackoffUntil.removeValue(forKey: session.id)
        } else {
            tap.teardown()
            activeTaps.removeValue(forKey: session.id)
            sessionTapOutputUIDs.removeValue(forKey: session.id)
            failedTapBackoffUntil[session.id] = Date().addingTimeInterval(Self.tapRetryBackoffSeconds)
        }
    }

#if DEBUG
    func setTestSessions(_ sessions: [AudioAppSession]) {
        self.activeSessions = sessions
        self.sessionTapOutputUIDs.removeAll()
        for s in sessions {
            savedVolumes[s.id] = s.volume
            savedMuted[s.id] = s.isMuted
        }
    }
#endif

    private static var processObjectListAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func allProcessObjectIDs() -> [AudioObjectID] {
        var addr = processObjectListAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &ids
        ) == noErr else {
            return []
        }
        return ids
    }

    private static func getProcessPID(_ objectID: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &pid)
        return status == noErr ? pid : nil
    }

    private static func getProcessBundleID(_ objectID: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rawCF: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &rawCF) { ptr in
            AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, ptr)
        }
        if status == noErr, let cfStr = rawCF?.takeRetainedValue() {
            return cfStr as String
        }
        return ""
    }

    private static func getProcessFlag(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var val: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &val)
        return status == noErr && val != 0
    }

    nonisolated static func normalizedProcessObjectIDs(_ ids: [AudioObjectID]) -> [AudioObjectID] {
        Array(Set(ids)).sorted()
    }

    nonisolated static func buildPIDMap<T>(
        _ pairs: [(pid_t, T)],
        uniquingKeysWith combine: (T, T) -> T = { first, _ in first }
    ) -> [pid_t: T] {
        Dictionary(
            pairs.filter { $0.0 > 0 },
            uniquingKeysWith: combine
        )
    }

    static func indexRunningApplications(_ apps: [NSRunningApplication]) -> (
        byPID: [pid_t: NSRunningApplication],
        regularByBundleID: [String: NSRunningApplication],
        regularApps: [NSRunningApplication]
    ) {
        let liveApps = apps.filter { !$0.isTerminated && $0.processIdentifier > 0 }
        let byPID = buildPIDMap(
            liveApps.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, second in
                first.activationPolicy == .regular ? first : second
            }
        )
        var regularApps: [NSRunningApplication] = []
        var regularByBundleID: [String: NSRunningApplication] = [:]
        for app in liveApps where app.activationPolicy == .regular {
            regularApps.append(app)
            if let bundleID = app.bundleIdentifier, !bundleID.isEmpty, regularByBundleID[bundleID] == nil {
                regularByBundleID[bundleID] = app
            }
        }
        return (byPID, regularByBundleID, regularApps)
    }

    nonisolated static func normalizeBundleID(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [
            ".helper", ".Helper", ".renderer", ".gpu", ".audio",
            ".WebContent", ".Networking", ".GPU", ".Plugin", ".plugin"
        ]
        var didStrip = true
        while didStrip {
            didStrip = false
            for suffix in suffixes where cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
                didStrip = true
                break
            }
        }
        if cleaned == "com.apple.WebKit" || cleaned.hasPrefix("com.apple.WebKit.") {
            return "com.apple.Safari"
        }
        return cleaned
    }

    private static func resolveHostApplication(
        pid: pid_t,
        rawBundleID: String,
        index: (
            byPID: [pid_t: NSRunningApplication],
            regularByBundleID: [String: NSRunningApplication],
            regularApps: [NSRunningApplication]
        )
    ) -> NSRunningApplication? {
        if let direct = index.byPID[pid], direct.activationPolicy == .regular {
            return direct
        }
        let normalized = normalizeBundleID(rawBundleID)
        if !normalized.isEmpty {
            if let exact = index.regularByBundleID[normalized] {
                return exact
            }
            if let prefixMatch = index.regularApps.first(where: {
                guard let bID = $0.bundleIdentifier, !bID.isEmpty else { return false }
                return normalized == bID || normalized.hasPrefix(bID + ".")
            }) {
                return prefixMatch
            }
        }
        if let helperApp = index.byPID[pid] {
            if let helperPath = (helperApp.bundleURL ?? helperApp.executableURL)?.standardizedFileURL.path {
                if let hostMatch = index.regularApps.first(where: {
                    guard let hostPath = $0.bundleURL?.standardizedFileURL.path else { return false }
                    let dirPrefix = hostPath.hasSuffix("/") ? hostPath : hostPath + "/"
                    return helperPath == hostPath || helperPath.hasPrefix(dirPrefix)
                }) {
                    return hostMatch
                }
            }
            return helperApp
        }
        return nil
    }

    private static func fallbackAppName(from bundleID: String, pid: pid_t) -> String {
        if let last = bundleID.split(separator: ".").last, !last.isEmpty {
            return String(last)
        }
        return ""
    }
}
