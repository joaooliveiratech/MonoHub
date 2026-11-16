import SwiftUI
import AVFoundation
import AppKit
import CoreImage

final class CameraPreviewContainerNSView: NSView {
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    var isMirrored: Bool = true
    var zoomScale: CGFloat = 1.0
    var cornerRadius: CGFloat = 14

    private var lastAppliedBounds: CGRect = .zero
    private var lastAppliedMirrored: Bool?
    private var lastAppliedZoom: CGFloat = -1
    private var lastAppliedRadius: CGFloat = -1
    private var lastFilterKey: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = cornerRadius
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attachPreviewLayer(_ newLayer: AVCaptureVideoPreviewLayer) {
        previewLayer?.removeFromSuperlayer()
        self.previewLayer = newLayer
        newLayer.videoGravity = .resizeAspectFill
        self.layer?.masksToBounds = true
        self.layer?.cornerCurve = .continuous
        self.layer?.cornerRadius = cornerRadius
        self.layer?.addSublayer(newLayer)
        lastAppliedBounds = .zero
        updateLayerGeometry(force: true)
    }

    func updateLayerGeometry(force: Bool = false) {
        guard let previewLayer, bounds.width > 0, bounds.height > 0 else { return }
        if !force
            && lastAppliedBounds == bounds
            && lastAppliedMirrored == isMirrored
            && abs(lastAppliedZoom - zoomScale) < 0.001
            && abs(lastAppliedRadius - cornerRadius) < 0.001 {
            return
        }
        lastAppliedBounds = bounds
        lastAppliedMirrored = isMirrored
        lastAppliedZoom = zoomScale
        lastAppliedRadius = cornerRadius

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.layer?.cornerRadius = cornerRadius
        previewLayer.bounds = bounds
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        let scaleX: CGFloat = (isMirrored ? -1.0 : 1.0) * max(1.0, zoomScale)
        let scaleY: CGFloat = max(1.0, zoomScale)
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: scaleX, y: scaleY))
        CATransaction.commit()
    }

    func applyFiltersIfNeeded(isStudioLight: Bool, isPortrait: Bool, exposureBias: Double) {
        guard let previewLayer else { return }
        let key = "\(isStudioLight)-\(isPortrait)-\(Int((exposureBias * 100).rounded()))"
        guard key != lastFilterKey else { return }
        lastFilterKey = key

        var filters: [CIFilter] = []
        if abs(exposureBias) > 0.01 || isStudioLight || isPortrait {
            if let colorControls = CIFilter(name: "CIColorControls") {
                colorControls.setDefaults()
                let brightness = Float(exposureBias * 0.14) + (isStudioLight ? 0.035 : 0.0)
                let contrast: Float = isStudioLight ? 1.12 : (isPortrait ? 1.04 : 1.0)
                let saturation: Float = isStudioLight ? 1.06 : 1.0
                colorControls.setValue(brightness, forKey: kCIInputBrightnessKey)
                colorControls.setValue(contrast, forKey: kCIInputContrastKey)
                colorControls.setValue(saturation, forKey: kCIInputSaturationKey)
                filters.append(colorControls)
            }
        }
        previewLayer.filters = filters.isEmpty ? nil : filters
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
    }
}

struct CameraPreviewNSView: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool
    let isStudioLight: Bool
    let isPortrait: Bool
    let exposureBias: Double
    var zoomScale: CGFloat = 1.0
    var cornerRadius: CGFloat = 14

    func makeNSView(context: Context) -> CameraPreviewContainerNSView {
        let view = CameraPreviewContainerNSView(frame: .zero)
        view.isMirrored = isMirrored
        view.zoomScale = zoomScale
        view.cornerRadius = cornerRadius

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        view.attachPreviewLayer(previewLayer)
        view.applyFiltersIfNeeded(isStudioLight: isStudioLight, isPortrait: isPortrait, exposureBias: exposureBias)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewContainerNSView, context: Context) {
        nsView.isMirrored = isMirrored
        nsView.zoomScale = zoomScale
        nsView.cornerRadius = cornerRadius
        if let previewLayer = nsView.previewLayer {
            if previewLayer.session !== session {
                previewLayer.session = session
            }
            nsView.updateLayerGeometry()
            nsView.applyFiltersIfNeeded(isStudioLight: isStudioLight, isPortrait: isPortrait, exposureBias: exposureBias)
        }
    }
}

struct CameraVignetteOverlay: View {
    let isStudioLight: Bool
    let isPortrait: Bool

    var body: some View {
        if isStudioLight || isPortrait {
            GeometryReader { geo in
                let radius = max(geo.size.width, geo.size.height)
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(isPortrait ? 0.22 : 0.12),
                        Color.black.opacity((isStudioLight && isPortrait) ? 0.68 : (isStudioLight ? 0.52 : 0.38))
                    ],
                    center: .center,
                    startRadius: radius * (isPortrait ? 0.22 : 0.28),
                    endRadius: radius * 0.72
                )
            }
            .allowsHitTesting(false)
        }
    }
}

struct CameraMirrorView: View {
    @Bindable private var mirrorManager = CameraMirrorManager.shared
    @State private var consumerID = "mirror-\(UUID().uuidString)"

    init() {}

    private var effectiveScale: CGFloat {
        let base = CGFloat(mirrorManager.zoomFactor)

        if mirrorManager.isCenterStageEnabled && !mirrorManager.hardwareCenterStageSupported {
            return max(base, 1.16)
        }
        return base
    }

    var body: some View {
        HStack(spacing: 14) {
            videoPreviewBox

            controlsPanel
        }
        .notchModule()
        .onAppear {
            mirrorManager.startSession(consumer: consumerID)
        }
        .onDisappear {
            mirrorManager.stopSession(consumer: consumerID)
        }
    }

    private var videoPreviewBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)

            if mirrorManager.isRunning {
                CameraPreviewNSView(
                    session: mirrorManager.captureSession,
                    isMirrored: mirrorManager.isMirrored,
                    isStudioLight: mirrorManager.isStudioLightEnabled,
                    isPortrait: mirrorManager.isPortraitEnabled,
                    exposureBias: mirrorManager.exposureBias,
                    zoomScale: effectiveScale,
                    cornerRadius: 14
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                CameraVignetteOverlay(
                    isStudioLight: mirrorManager.isStudioLightEnabled,
                    isPortrait: mirrorManager.isPortraitEnabled
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if mirrorManager.isAccessDenied {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NotchTheme.secondaryText)
                    Text(localized("Camera access denied"))
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.secondaryText)
                    Button(localized("Open Settings")) {
                        mirrorManager.openPrivacySettings()
                    }
                    .buttonStyle(NotchSecondaryButtonStyle())
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text(localized("Starting camera…"))
                        .font(NotchTheme.caption)
                        .foregroundStyle(NotchTheme.tertiaryText)
                }
            }

            if mirrorManager.showGrid {
                CameraGridOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
            }

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    mirrorManager.isRingLightEnabled
                        ? Color(red: 1.0, green: 0.96, blue: 0.88)
                        : Color.white.opacity(0.14),
                    lineWidth: mirrorManager.isRingLightEnabled ? 4.5 : 1
                )
                .shadow(
                    color: mirrorManager.isRingLightEnabled ? Color(red: 1.0, green: 0.95, blue: 0.82).opacity(0.85) : .clear,
                    radius: mirrorManager.isRingLightEnabled ? 12 : 0
                )
                .allowsHitTesting(false)

            VStack {
                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6.5, height: 6.5)
                            .shadow(color: .green, radius: 3)

                        Text(localized("LIVE"))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))

                    if mirrorManager.isCenterStageEnabled {
                        activeBadge(icon: "person.crop.rectangle.fill", text: localized("FOLLOW"), tint: .green)
                    }
                    if mirrorManager.isStudioLightEnabled {
                        activeBadge(icon: "sun.max.fill", text: localized("LIGHT"), tint: .yellow)
                    }
                    if mirrorManager.isPortraitEnabled {
                        activeBadge(icon: "camera.aperture", text: localized("PORTRAIT"), tint: .cyan)
                    }

                    Spacer()
                }
                .padding(8)

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        NotchHaptics.tap()
                        mirrorManager.cycleZoom()
                    } label: {
                        Text(String(format: "%.2gx", mirrorManager.zoomFactor))
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(mirrorManager.zoomFactor > 1.01 ? Color.yellow : Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(localized("Toggle Zoom (1x / 1.25x / 1.5x)"))

                    Button {
                        NotchHaptics.tap()
                        mirrorManager.toggleGrid()
                    } label: {
                        Image(systemName: "squareshape.split.3x3")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(mirrorManager.showGrid ? Color.yellow : Color.white.opacity(0.85))
                            .frame(width: 24, height: 22)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(localized("3x3 Framing Grid"))

                    Spacer()

                    Button {
                        NotchHaptics.tap()
                        mirrorManager.toggleMirror()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                                .font(.system(size: 8.5))
                            Text(mirrorManager.isMirrored ? localized("Mirrored") : localized("Natural"))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(localized("Toggle mirrored or natural orientation"))
                }
                .padding(8)
            }
        }
        .frame(width: 256)
        .frame(maxHeight: .infinity)
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 8) {
                NotchSectionLabel(localized("Camera"), systemImage: "video.badge.checkmark", tint: .purple)

                Spacer()

                cameraDeviceMenu
            }

            let columns = [
                GridItem(.flexible(), spacing: 7),
                GridItem(.flexible(), spacing: 7)
            ]

            LazyVGrid(columns: columns, spacing: 7) {
                effectToggleCard(
                    title: localized("Follow"),
                    subtitle: localized("Center Stage"),
                    icon: "person.crop.rectangle.fill",
                    tint: .green,
                    isOn: mirrorManager.isCenterStageEnabled
                ) {
                    mirrorManager.toggleCenterStage()
                }

                effectToggleCard(
                    title: localized("Studio Light"),
                    subtitle: localized("Face enhancement"),
                    icon: "sun.max.fill",
                    tint: .yellow,
                    isOn: mirrorManager.isStudioLightEnabled
                ) {
                    mirrorManager.toggleStudioLight()
                }

                effectToggleCard(
                    title: localized("Portrait Mode"),
                    subtitle: localized("Focus on you"),
                    icon: "camera.aperture",
                    tint: .cyan,
                    isOn: mirrorManager.isPortraitEnabled
                ) {
                    mirrorManager.togglePortrait()
                }

                effectToggleCard(
                    title: localized("Border Light"),
                    subtitle: localized("Ring Light"),
                    icon: "circle.dashed.inset.filled",
                    tint: .orange,
                    isOn: mirrorManager.isRingLightEnabled
                ) {
                    mirrorManager.toggleRingLight()
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.secondaryText)

                NotchCapsuleSlider(
                    value: $mirrorManager.exposureBias,
                    range: -1.0...1.0,
                    tint: .yellow,
                    trackHeight: 5,
                    expandedHeight: 8
                )

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow)

                if abs(mirrorManager.exposureBias) > 0.05 || mirrorManager.isCenterStageEnabled || mirrorManager.isStudioLightEnabled || mirrorManager.isPortraitEnabled || mirrorManager.isRingLightEnabled || mirrorManager.zoomFactor > 1.01 {
                    Button {
                        NotchHaptics.tap()
                        withAnimation(NotchTheme.content) {
                            mirrorManager.resetEffects()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(localized("Reset camera adjustments"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cameraDeviceMenu: some View {
        Menu {
            ForEach(mirrorManager.availableDevices, id: \.uniqueID) { device in
                Button {
                    NotchHaptics.tap()
                    mirrorManager.selectDevice(device)
                } label: {
                    HStack {
                        Text(device.localizedName)
                        if device.uniqueID == mirrorManager.currentDevice?.uniqueID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 9.5))
                Text(mirrorManager.currentDevice?.localizedName ?? localized("Camera"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(NotchTheme.controlFill))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func effectToggleCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            NotchHaptics.tap()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                action()
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isOn ? tint : Color.white.opacity(0.1))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 0.5) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.88))
                        .lineLimit(1)
                    Text(isOn ? localized("Enabled") : subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isOn ? tint : NotchTheme.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isOn ? tint.opacity(0.18) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(isOn ? tint.opacity(0.45) : Color.white.opacity(0.07), lineWidth: 0.75)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func activeBadge(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .bold))
            Text(text)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(tint))
    }
}

private struct CameraGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: (w * 2) / 3, y: 0))
                path.addLine(to: CGPoint(x: (w * 2) / 3, y: h))
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: (h * 2) / 3))
                path.addLine(to: CGPoint(x: w, y: (h * 2) / 3))
            }
            .stroke(Color.white.opacity(0.28), lineWidth: 0.75)
        }
    }
}
