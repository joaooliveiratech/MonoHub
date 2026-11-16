import AppKit
@preconcurrency import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class CameraMirrorManager {
    static let shared = CameraMirrorManager()

    private(set) var isRunning: Bool = false
    private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined
    var isMirrored: Bool {
        didSet { NotchPreferences.shared.cameraIsMirrored = isMirrored }
    }
    private(set) var availableDevices: [AVCaptureDevice] = []
    private(set) var currentDevice: AVCaptureDevice?

    var isCenterStageEnabled: Bool {
        didSet {
            NotchPreferences.shared.cameraCenterStageEnabled = isCenterStageEnabled
            applyHardwareCenterStage()
        }
    }

    var isStudioLightEnabled: Bool {
        didSet { NotchPreferences.shared.cameraStudioLightEnabled = isStudioLightEnabled }
    }

    var isPortraitEnabled: Bool {
        didSet { NotchPreferences.shared.cameraPortraitEnabled = isPortraitEnabled }
    }

    var isRingLightEnabled: Bool {
        didSet { NotchPreferences.shared.cameraRingLightEnabled = isRingLightEnabled }
    }

    var showGrid: Bool {
        didSet { NotchPreferences.shared.cameraShowGrid = showGrid }
    }

    var zoomFactor: Double {
        didSet { NotchPreferences.shared.cameraZoomFactor = zoomFactor }
    }

    var exposureBias: Double {
        didSet { NotchPreferences.shared.cameraExposureBias = exposureBias }
    }

    private(set) var hardwareCenterStageSupported: Bool = false

    @ObservationIgnored private(set) lazy var captureSession = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.antigravity.monohub.cameraQueue", qos: .userInitiated)
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var sessionGeneration = 0
    @ObservationIgnored private var activeConsumers: Set<String> = []
    @ObservationIgnored private var stopDebounceTask: Task<Void, Never>?

    private init() {
        let prefs = NotchPreferences.shared
        isMirrored = prefs.cameraIsMirrored
        isCenterStageEnabled = prefs.cameraCenterStageEnabled
        isStudioLightEnabled = prefs.cameraStudioLightEnabled
        isPortraitEnabled = prefs.cameraPortraitEnabled
        isRingLightEnabled = prefs.cameraRingLightEnabled
        showGrid = prefs.cameraShowGrid
        zoomFactor = prefs.cameraZoomFactor
        exposureBias = prefs.cameraExposureBias
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    var isAuthorized: Bool { authorizationStatus == .authorized }

    var isAccessDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func refreshAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status != authorizationStatus {
            authorizationStatus = status
        }
    }

    func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices
        availableDevices = devices
        if let current = currentDevice, devices.contains(where: { $0.uniqueID == current.uniqueID }) {
            return updateDeviceCapabilities()
        }
        currentDevice = devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? devices.first(where: { $0.position == .front })
            ?? devices.first
        updateDeviceCapabilities()
    }

    private func updateDeviceCapabilities() {
        guard let device = currentDevice else {
            hardwareCenterStageSupported = false
            return
        }
        hardwareCenterStageSupported = device.activeFormat.isCenterStageSupported
            || device.formats.contains(where: { $0.isCenterStageSupported })
    }

    private func applyHardwareCenterStage() {
        guard hardwareCenterStageSupported else { return }
        AVCaptureDevice.centerStageControlMode = .cooperative
        if AVCaptureDevice.isCenterStageEnabled != isCenterStageEnabled {
            AVCaptureDevice.isCenterStageEnabled = isCenterStageEnabled
        }
    }

    func startSession(consumer: String = "default") {
        stopDebounceTask?.cancel()
        stopDebounceTask = nil
        activeConsumers.insert(consumer)
        wantsRunning = true
        refreshAuthorization()
        switch authorizationStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                Task { @MainActor in
                    let manager = CameraMirrorManager.shared
                    manager.refreshAuthorization()
                    if manager.wantsRunning && manager.isAuthorized {
                        manager.configureAndStart()
                    }
                }
            }
        case .authorized:
            configureAndStart()
        default:
            break
        }
    }

    private func configureAndStart(forceReconfigure: Bool = false) {
        guard wantsRunning, (!isRunning || forceReconfigure) else { return }
        refreshDevices()
        guard let device = currentDevice else { return }
        applyHardwareCenterStage()

        sessionGeneration += 1
        let generation = sessionGeneration
        sessionQueue.async { [session = captureSession] in
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            if !session.isRunning {
                session.startRunning()
            }
            let running = session.isRunning

            Task { @MainActor in
                let manager = CameraMirrorManager.shared
                guard manager.wantsRunning else {
                    manager.tearDownSession()
                    return
                }
                guard generation == manager.sessionGeneration else { return }
                manager.isRunning = running
            }
        }
    }

    func stopSession(consumer: String? = nil) {
        if let consumer {
            activeConsumers.remove(consumer)
            guard activeConsumers.isEmpty else { return }
            stopDebounceTask?.cancel()
            stopDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                guard let self, !Task.isCancelled, self.activeConsumers.isEmpty else { return }
                self.performStopSession()
            }
        } else {
            stopDebounceTask?.cancel()
            stopDebounceTask = nil
            activeConsumers.removeAll()
            performStopSession()
        }
    }

    private func performStopSession() {
        wantsRunning = false
        sessionGeneration += 1
        if isRunning {
            isRunning = false
        }
        tearDownSession()
    }

    private func tearDownSession() {
        sessionQueue.async { [session = captureSession] in
            if session.isRunning {
                session.stopRunning()
            }
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            session.commitConfiguration()
        }
    }

    func releaseResources() {
        guard wantsRunning || isRunning || !availableDevices.isEmpty || currentDevice != nil else { return }
        stopSession(consumer: nil)
        availableDevices = []
        currentDevice = nil
    }

    func selectDevice(_ device: AVCaptureDevice) {
        currentDevice = device
        updateDeviceCapabilities()
        if wantsRunning {
            configureAndStart(forceReconfigure: true)
        }
    }

    func openPrivacySettings() {
        guard !AppInfo.isRunningTests else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    func toggleMirror() {
        isMirrored.toggle()
    }

    func toggleCenterStage() {
        isCenterStageEnabled.toggle()
    }

    func toggleStudioLight() {
        isStudioLightEnabled.toggle()
    }

    func togglePortrait() {
        isPortraitEnabled.toggle()
    }

    func toggleRingLight() {
        isRingLightEnabled.toggle()
    }

    func toggleGrid() {
        showGrid.toggle()
    }

    func cycleZoom() {
        if zoomFactor < 1.15 {
            zoomFactor = 1.25
        } else if zoomFactor < 1.4 {
            zoomFactor = 1.5
        } else {
            zoomFactor = 1.0
        }
    }

    func resetEffects() {
        isCenterStageEnabled = false
        isStudioLightEnabled = false
        isPortraitEnabled = false
        isRingLightEnabled = false
        showGrid = false
        zoomFactor = 1.0
        exposureBias = 0.0
    }
}
