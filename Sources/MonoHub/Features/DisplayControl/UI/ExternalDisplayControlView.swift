import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DisplayControlSubTab: String, CaseIterable, Identifiable {
    case monitors = "monitors"
    case resolutions = "resolutions"
    case colorXDR = "colorXDR"
    case virtualScreens = "virtualScreens"
    case pipStream = "pipStream"
    case layoutEDID = "layoutEDID"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monitors: return localized("Monitors & DDC")
        case .resolutions: return localized("Resolutions & HiDPI")
        case .colorXDR: return localized("Color & XDR")
        case .virtualScreens: return localized("Virtual Screens")
        case .pipStream: return localized("PiP & Teleprompter")
        case .layoutEDID: return localized("Layout & EDID")
        }
    }

    var systemImage: String {
        switch self {
        case .monitors: return "display.2"
        case .resolutions: return "aspectratio"
        case .colorXDR: return "sun.max.trianglebadge.exclamationmark"
        case .virtualScreens: return "rectangle.on.rectangle.dashed"
        case .pipStream: return "pip"
        case .layoutEDID: return "memorychip"
        }
    }
}

struct ExternalDisplayControlView: View {
    @Bindable private var preferences = DisplayControlPreferences.shared
    private let manager = ExternalDisplayManager.shared
    private let pipEngine = DisplayPiPStreamEngine.shared

    @State private var selectedTab: DisplayControlSubTab = .monitors
    @State private var expandedDisplayUUIDs: Set<String> = []
    @State private var isAdvancedTuningExpanded = false

    @State private var selectedDisplayIDForRes: CGDirectDisplayID = 0
    @State private var hiDPIOnlyFilter = true
    @State private var favoritesOnlyFilter = false
    @State private var customResWidthText = "2560"
    @State private var customResHeightText = "1440"

    @State private var newVirtualName = "MonoHub Virtual 4K"
    @State private var newVirtualAspect: VirtualAspectRatio = .ratio16x9
    @State private var newVirtualRefresh: Double = 60.0
    @State private var newVirtualHiDPI = true
    @State private var newVirtualAutoConnect = false

    @State private var pipSourceDisplayID: CGDirectDisplayID = 0
    @State private var pipFlipMode: TeleprompterFlipMode = .none
    @State private var pipCropPreset: PiPCropPreset = .full
    @State private var pipOpacity: Double = 1.0
    @State private var pipClickThrough = false
    @State private var pipAlwaysOnTop = true

    @State private var newLayoutAnchorName = "Workstation Layout"
    @State private var selectedDisplayIDForEDID: CGDirectDisplayID = 0
    @State private var overrideForceRGB = true
    @State private var overrideUnlockNightShift = true
    @State private var showFactoryResetConfirmForDisplay: ExternalDisplayDevice?

    var body: some View {
        VStack(spacing: 0) {
            subTabHeader
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .monitors:
                        globalSettingsBanner
                        displaysList
                        advancedTuningSection
                    case .resolutions:
                        resolutionsAndHiDPISection
                    case .colorXDR:
                        colorAndXDRSection
                    case .virtualScreens:
                        virtualScreensSection
                    case .pipStream:
                        pipAndTeleprompterSection
                    case .layoutEDID:
                        layoutAndEDIDSection
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            manager.refreshDisplays()
            syncDefaultSelectedDisplays()
        }
        .onChange(of: manager.displays) { _, _ in
            syncDefaultSelectedDisplays()
        }
        .alert(
            localized("Factory Reset Display?"),
            isPresented: Binding(
                get: { showFactoryResetConfirmForDisplay != nil },
                set: { if !$0 { showFactoryResetConfirmForDisplay = nil } }
            ),
            presenting: showFactoryResetConfirmForDisplay
        ) { display in
            Button(localized("Cancel"), role: .cancel) {
                showFactoryResetConfirmForDisplay = nil
            }
            Button(localized("Factory Reset"), role: .destructive) {
                manager.sendFactoryReset(displayID: display.id)
                showFactoryResetConfirmForDisplay = nil
            }
        } message: { display in
            Text(localized("This sends DDC/CI VCP 0x04 to restore hardware factory settings on %@.", display.name))
        }
    }

    private func syncDefaultSelectedDisplays() {
        if let first = manager.displays.first {
            if selectedDisplayIDForRes == 0 || !manager.displays.contains(where: { $0.id == selectedDisplayIDForRes }) {
                selectedDisplayIDForRes = first.id
            }
            if pipSourceDisplayID == 0 || !manager.displays.contains(where: { $0.id == pipSourceDisplayID }) {
                pipSourceDisplayID = first.id
            }
            if selectedDisplayIDForEDID == 0 || !manager.displays.contains(where: { $0.id == selectedDisplayIDForEDID }) {
                selectedDisplayIDForEDID = first.id
            }
        }
    }

    private var subTabHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DisplayControlSubTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.cyan.opacity(0.18) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.cyan.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                        .foregroundStyle(isSelected ? Color.cyan : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private var globalSettingsBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "display.2")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 36, height: 36)
                    .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("External Display Control (DDC/CI)"))
                        .font(.headline)
                    Text(localized("Hardware brightness, volume, and contrast control via HDMI, DisplayPort, and Thunderbolt (BetterDisplay Pro inspired)."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $preferences.isDDCEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(localized("Keyboard Control Target"), systemImage: preferences.targetMode.systemImage)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $preferences.targetMode) {
                        ForEach(DDCTargetMode.allCases) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 230)
                }

                Text(preferences.targetMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 20) {
                Toggle(localized("Control external volume with F10/F11/F12"), isOn: $preferences.enableVolumeKeys)
                    .font(.system(size: 12.5))
                    .toggleStyle(.checkbox)

                Toggle(localized("Show monitor name in Notch HUD"), isOn: $preferences.showDisplayTitleInHUD)
                    .font(.system(size: 12.5))
                    .toggleStyle(.checkbox)

                Toggle(localized("Sync brightness with MacBook screen"), isOn: $preferences.syncBrightnessWithBuiltIn)
                    .font(.system(size: 12.5))
                    .toggleStyle(.checkbox)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var displaysList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(localized("Connected Displays (%d)", manager.displays.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    XDRAndOverlayEngine.shared.restoreAllBlackouts()
                    manager.refreshDisplays()
                } label: {
                    Label(localized("Restore Blackouts"), systemImage: "sun.max")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    manager.refreshDisplays(readDDCValues: true)
                } label: {
                    Label(localized("Detect Displays"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if manager.displays.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(localized("No displays detected"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(30)
            } else {
                ForEach(manager.displays) { display in
                    displayCard(display)
                }
            }
        }
    }

    private func displayCard(_ display: ExternalDisplayDevice) -> some View {
        let isExpanded = expandedDisplayUUIDs.contains(display.uuid)
        let config = preferences.config(for: display.uuid)
        let maxBrightnessLimit: Float = (config.xdrConfig.isEnabled && display.supportsXDRBoost) ? 2.0 : 1.0

        return VStack(alignment: .leading, spacing: 14) {

            HStack(spacing: 10) {
                Image(systemName: display.connectionType.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(display.isBuiltIn ? .indigo : (display.isVirtual ? .purple : .cyan))
                    .frame(width: 32, height: 32)
                    .background((display.isBuiltIn ? Color.indigo : (display.isVirtual ? Color.purple : Color.cyan)).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(display.name)
                            .font(.system(size: 14, weight: .semibold))
                        if display.isMainDisplay {
                            Text(localized("Main"))
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.yellow.opacity(0.18)))
                                .foregroundStyle(.orange)
                        }
                        if display.isBuiltIn {
                            Text(localized("Built-in"))
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.indigo.opacity(0.15)))
                                .foregroundStyle(.indigo)
                        } else {
                            Text(display.connectionType.localizedTitle)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.cyan.opacity(0.15)))
                                .foregroundStyle(.cyan)

                            if display.supportsDDC {
                                Text("DDC/CI")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.15)))
                                    .foregroundStyle(.green)
                            }
                        }
                        if display.isHiDPI {
                            Text("HiDPI")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.mint.opacity(0.18)))
                                .foregroundStyle(.mint)
                        }
                        if display.supportsXDRBoost {
                            Text("XDR")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("\(display.resolutionString) pt (\(Int(display.pixelSize.width))×\(Int(display.pixelSize.height)) px @ \(Int(display.refreshRate.rounded())) Hz) • UUID: \(display.uuid.prefix(8))…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !display.isMainDisplay {
                    Button {
                        _ = ResolutionAndLayoutEngine.shared.setMainDisplay(display.id)
                        manager.refreshDisplays()
                    } label: {
                        Label(localized("Set Main"), systemImage: "crown")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    manager.toggleBlackout(for: display)
                } label: {
                    Label(
                        display.isBlackedOut ? localized("Unblank") : localized("Blackout"),
                        systemImage: display.isBlackedOut ? "eye" : "eye.slash"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    if isExpanded {
                        expandedDisplayUUIDs.remove(display.uuid)
                    } else {
                        expandedDisplayUUIDs.insert(display.uuid)
                    }
                } label: {
                    Label(
                        isExpanded ? localized("Hide Pro Settings") : localized("Pro Settings"),
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: display.brightness > 1.0 ? "sun.max.trianglebadge.exclamationmark.fill" : "sun.max.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(display.brightness > 1.0 ? .orange : .yellow)
                        .frame(width: 20)

                    Text(localized("Brightness"))
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 80, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { display.brightness },
                            set: { manager.setBrightness(displayID: display.id, value: $0) }
                        ),
                        in: 0.0...maxBrightnessLimit
                    )

                    Text("\(Int(round(display.brightness * 100)))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(display.brightness > 1.0 ? .orange : .primary)
                        .frame(width: 48, alignment: .trailing)
                }

                if !display.isBuiltIn && display.supportsVolume {
                    HStack(spacing: 10) {
                        Image(systemName: display.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(display.isMuted ? .red : .teal)
                            .frame(width: 20)

                        Text(localized("Volume"))
                            .font(.system(size: 12.5, weight: .medium))
                            .frame(width: 80, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { display.volume },
                                set: { manager.setVolume(displayID: display.id, value: $0) }
                            ),
                            in: 0.0...1.0
                        )

                        Text(display.isMuted ? localized("Muted") : "\(Int(round(display.volume * 100)))%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(display.isMuted ? .red : .primary)
                            .frame(width: 50, alignment: .trailing)

                        Button {
                            manager.toggleMute(displayID: display.id)
                        } label: {
                            Image(systemName: display.isMuted ? "speaker.slash" : "speaker")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if !display.isBuiltIn && display.supportsDDC {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 14))
                            .foregroundStyle(.purple)
                            .frame(width: 20)

                        Text(localized("Contrast"))
                            .font(.system(size: 12.5, weight: .medium))
                            .frame(width: 80, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { display.contrast },
                                set: { manager.setContrast(displayID: display.id, value: $0) }
                            ),
                            in: 0.0...1.0
                        )

                        Text("\(Int(round(display.contrast * 100)))%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "triangle.lefthalf.filled")
                            .font(.system(size: 14))
                            .foregroundStyle(.mint)
                            .frame(width: 20)

                        Text(localized("Sharpness"))
                            .font(.system(size: 12.5, weight: .medium))
                            .frame(width: 80, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { display.sharpness },
                                set: { manager.setSharpness(displayID: display.id, value: $0) }
                            ),
                            in: 0.0...1.0
                        )

                        Text("\(Int(round(display.sharpness * 100)))%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            if !display.isBuiltIn && display.supportsDDC {
                Divider()

                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(localized("Input Source:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("", selection: Binding(
                            get: { display.inputSource ?? .hdmi1 },
                            set: { manager.setInputSource(displayID: display.id, source: $0) }
                        )) {
                            ForEach(DDCProtocol.InputSource.allCases) { source in
                                Label(source.title, systemImage: source.systemImage).tag(source)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 155)
                    }

                    HStack(spacing: 6) {
                        Text(localized("Color Preset:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("", selection: Binding(
                            get: { display.colorPreset ?? .standard6500K },
                            set: { manager.setColorPreset(displayID: display.id, preset: $0) }
                        )) {
                            ForEach(DDCProtocol.ColorPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Button {
                            manager.setPowerState(displayID: display.id, state: .standby)
                        } label: {
                            Label(localized("Standby"), systemImage: "moon.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            manager.setPowerState(displayID: display.id, state: .off)
                        } label: {
                            Label(localized("Turn Off"), systemImage: "power")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            showFactoryResetConfirmForDisplay = display
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(localized("Factory Reset"))
                    }
                }
            }

            if isExpanded {
                Divider()
                proConfigurationSection(display: display, config: config)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func proConfigurationSection(display: ExternalDisplayDevice, config: DisplayDeviceConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("BetterDisplay Pro Settings for %@", display.name))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(localized("Dimming Mode"))
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { config.dimmingMode },
                        set: { newMode in
                            preferences.updateConfig(for: display.uuid) { $0.dimmingMode = newMode }
                        }
                    )) {
                        ForEach(DisplayDimmingMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }

                Text(config.dimmingMode.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                localized("Enable Sub-Zero Overlay Dimming down to 0% pitch black"),
                isOn: Binding(
                    get: { config.allowSubZeroOverlayDimming },
                    set: { val in
                        preferences.updateConfig(for: display.uuid) { $0.allowSubZeroOverlayDimming = val }
                    }
                )
            )
            .font(.system(size: 12.5))
            .toggleStyle(.checkbox)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("Hardware Brightness Range Limits"))
                    .font(.system(size: 12.5, weight: .medium))

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("Hardware Minimum: %d%%", Int(round(config.minHardwareBrightness * 100))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { config.minHardwareBrightness },
                                set: { val in
                                    preferences.updateConfig(for: display.uuid) { $0.minHardwareBrightness = val }
                                }
                            ),
                            in: 0.0...0.5
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("Hardware Maximum: %d%%", Int(round(config.maxHardwareBrightness * 100))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { config.maxHardwareBrightness },
                                set: { val in
                                    preferences.updateConfig(for: display.uuid) { $0.maxHardwareBrightness = val }
                                }
                            ),
                            in: 0.5...1.0
                        )
                    }
                }

                Text(localized("Sets the physical backlight boundaries. In Combined mode, brightness levels below the minimum hardware limit seamlessly transition into software gamma dimming."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Brightness Scale Curve"))
                        .font(.system(size: 12.5, weight: .medium))
                    Text(config.brightnessCurve.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { config.brightnessCurve },
                    set: { newCurve in
                        preferences.updateConfig(for: display.uuid) { $0.brightnessCurve = newCurve }
                    }
                )) {
                    ForEach(BrightnessCurve.allCases) { curve in
                        Text(curve.title).tag(curve)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }

            if !display.isBuiltIn && display.supportsDDC {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Hardware DDC RGB Video Gain (0x16 / 0x18 / 0x1A)"))
                        .font(.system(size: 12.5, weight: .medium))

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("R: \(Int(round(display.redGainDDC * 100)))%")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Slider(
                                value: Binding(
                                    get: { display.redGainDDC },
                                    set: { manager.setHardwareRGBGain(displayID: display.id, red: $0, green: display.greenGainDDC, blue: display.blueGainDDC) }
                                ),
                                in: 0.0...1.0
                            )
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("G: \(Int(round(display.greenGainDDC * 100)))%")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Slider(
                                value: Binding(
                                    get: { display.greenGainDDC },
                                    set: { manager.setHardwareRGBGain(displayID: display.id, red: display.redGainDDC, green: $0, blue: display.blueGainDDC) }
                                ),
                                in: 0.0...1.0
                            )
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("B: \(Int(round(display.blueGainDDC * 100)))%")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Slider(
                                value: Binding(
                                    get: { display.blueGainDDC },
                                    set: { manager.setHardwareRGBGain(displayID: display.id, red: display.redGainDDC, green: display.greenGainDDC, blue: $0) }
                                ),
                                in: 0.0...1.0
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var advancedTuningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                isAdvancedTuningExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(.orange)
                    Text(localized("Advanced DDC/CI Protocol Tuning (BetterDisplay Pro)"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: isAdvancedTuningExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isAdvancedTuningExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("DDC Write Delay: %d ms", preferences.ddcWriteSleepMs))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(localized("Pause between consecutive I2C write packets. Lower is faster; higher improves compatibility."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { Double(preferences.ddcWriteSleepMs) },
                                set: { preferences.ddcWriteSleepMs = Int($0) }
                            ),
                            in: 5...100,
                            step: 5
                        )
                        .frame(width: 180)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("DDC Read Response Wait: %d ms", preferences.ddcReadSleepMs))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(localized("Time given to monitor microcontroller to prepare reply buffer."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { Double(preferences.ddcReadSleepMs) },
                                set: { preferences.ddcReadSleepMs = Int($0) }
                            ),
                            in: 10...150,
                            step: 5
                        )
                        .frame(width: 180)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("I2C Packet Retry Count: %d", preferences.ddcRetryAttempts))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(localized("Number of retry attempts if communication packet fails or times out."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper("\(preferences.ddcRetryAttempts)", value: $preferences.ddcRetryAttempts, in: 1...5)
                            .frame(width: 120)
                    }

                    Divider()

                    Toggle(localized("Read hardware values on app startup and monitor connect"), isOn: $preferences.readOnStartup)
                        .font(.system(size: 12.5))
                        .toggleStyle(.checkbox)

                    Toggle(localized("Auto-blackout built-in screen when external monitor connects"), isOn: $preferences.autoBlackoutBuiltInOnExternal)
                        .font(.system(size: 12.5))
                        .toggleStyle(.checkbox)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var resolutionsAndHiDPISection: some View {
        let selectedDisplay = manager.displays.first(where: { $0.id == selectedDisplayIDForRes }) ?? manager.displays.first
        let allModes = selectedDisplay.flatMap { manager.availableModesByDisplay[$0.id] } ?? []
        let cfg = selectedDisplay.map { preferences.config(for: $0.uuid) } ?? DisplayDeviceConfig()

        let filteredModes = allModes.filter { mode in
            if hiDPIOnlyFilter && !mode.isHiDPI { return false }
            if favoritesOnlyFilter && !cfg.favoriteResolutionModeIDs.contains(mode.id) { return false }
            return true
        }

        return VStack(alignment: .leading, spacing: 16) {

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Flexible HiDPI Scaling, Refresh Rate & Rotation"))
                        .font(.headline)
                    Text(localized("Switch between Retina HiDPI and native LoDPI modes, adjust refresh rates, and rotate displays."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !manager.displays.isEmpty {
                    Picker(localized("Display"), selection: $selectedDisplayIDForRes) {
                        ForEach(manager.displays) { d in
                            Text(d.name).tag(d.id)
                        }
                    }
                    .frame(width: 240)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )

            if let display = selectedDisplay {

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("Active Resolution"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(display.resolutionString) \(display.isHiDPI ? "HiDPI" : "LoDPI")")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(localized("Framebuffer: %d × %d px @ %d Hz", Int(display.pixelSize.width), Int(display.pixelSize.height), Int(display.refreshRate.rounded())))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(localized("Display Rotation"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(DisplayRotation.allCases) { rot in
                                Button {
                                    _ = ResolutionAndLayoutEngine.shared.setRotation(rot, for: display.id)
                                    manager.refreshDisplays()
                                } label: {
                                    Text(rot.shortTitle)
                                        .font(.system(size: 12, weight: display.rotation == rot ? .bold : .regular))
                                }
                                .buttonStyle(.bordered)
                                .tint(display.rotation == rot ? .cyan : nil)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                )

                HStack(spacing: 16) {
                    Toggle(localized("HiDPI (Retina) Modes Only"), isOn: $hiDPIOnlyFilter)
                        .font(.system(size: 12.5))
                        .toggleStyle(.checkbox)

                    Toggle(localized("Favorites Only"), isOn: $favoritesOnlyFilter)
                        .font(.system(size: 12.5))
                        .toggleStyle(.checkbox)

                    Spacer()

                    Text(localized("%d modes available", filteredModes.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    ForEach(filteredModes.prefix(24)) { mode in
                        let isFav = cfg.favoriteResolutionModeIDs.contains(mode.id)
                        HStack(spacing: 12) {
                            Button {
                                preferences.updateConfig(for: display.uuid) { c in
                                    if let idx = c.favoriteResolutionModeIDs.firstIndex(of: mode.id) {
                                        c.favoriteResolutionModeIDs.remove(at: idx)
                                    } else {
                                        c.favoriteResolutionModeIDs.append(mode.id)
                                    }
                                }
                            } label: {
                                Image(systemName: isFav ? "star.fill" : "star")
                                    .foregroundStyle(isFav ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)

                            Text(mode.resolutionLabel)
                                .font(.system(size: 13.5, weight: mode.isCurrent ? .bold : .medium, design: .rounded))
                                .frame(width: 115, alignment: .leading)

                            if mode.isHiDPI {
                                Text("HiDPI")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.mint.opacity(0.18)))
                                    .foregroundStyle(.mint)
                            }

                            if mode.isNative {
                                Text(localized("Native"))
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.blue.opacity(0.18)))
                                    .foregroundStyle(.blue)
                            }

                            Text(mode.framebufferLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(mode.aspectRatioString)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))

                            Spacer()

                            Text(mode.refreshRateLabel)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)

                            if mode.isCurrent {
                                Text(localized("Active"))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.green)
                                    .frame(width: 70)
                            } else {
                                Button(localized("Apply")) {
                                    _ = ResolutionAndLayoutEngine.shared.applyMode(mode, to: display.id)
                                    manager.refreshDisplays()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.cyan)
                                .controlSize(.small)
                                .frame(width: 70)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(mode.isCurrent ? Color.cyan.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("Custom Scaled HiDPI Resolutions (Override List)"))
                        .font(.system(size: 13, weight: .semibold))

                    HStack(spacing: 10) {
                        TextField(localized("Width"), text: $customResWidthText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Text("×")
                        TextField(localized("Height"), text: $customResHeightText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)

                        Button {
                            if let w = Int(customResWidthText), let h = Int(customResHeightText), w >= 800, h >= 600 {
                                let spec = CustomScaledResolutionSpec(
                                    logicalWidth: w,
                                    logicalHeight: h,
                                    hiDPI: true,
                                    label: "\(w) × \(h) HiDPI (\(w * 2)×\(h * 2))"
                                )
                                preferences.updateConfig(for: display.uuid) { c in
                                    if !c.customScaledResolutions.contains(spec) {
                                        c.customScaledResolutions.append(spec)
                                    }
                                }
                            }
                        } label: {
                            Label(localized("Add HiDPI Resolution"), systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    FlowLayoutChips(items: cfg.customScaledResolutions) { spec in
                        HStack(spacing: 6) {
                            Text(spec.label)
                                .font(.caption2)
                            Button {
                                preferences.updateConfig(for: display.uuid) { c in
                                    c.customScaledResolutions.removeAll { $0.id == spec.id }
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.cyan.opacity(0.12)))
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                )
            }
        }
    }

    private var colorAndXDRSection: some View {
        let selectedDisplay = manager.displays.first(where: { $0.id == selectedDisplayIDForRes }) ?? manager.displays.first
        let cfg = selectedDisplay.map { preferences.config(for: $0.uuid) } ?? DisplayDeviceConfig()
        let colorAdj = cfg.colorAdjustment
        let xdrCfg = cfg.xdrConfig

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("XDR/HDR Extra Brightness & Software Color Calibration"))
                        .font(.headline)
                    Text(localized("Unlock XDR brightness up to 1600 nits and fine-tune Kelvin color temperature, RGB channels, gamma, and filters."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !manager.displays.isEmpty {
                    Picker(localized("Display"), selection: $selectedDisplayIDForRes) {
                        ForEach(manager.displays) { d in
                            Text(d.name).tag(d.id)
                        }
                    }
                    .frame(width: 240)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )

            if let display = selectedDisplay {

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sun.max.trianglebadge.exclamationmark.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("XDR / HDR Extra Brightness Upscaling (100% – 200%)"))
                                .font(.system(size: 13.5, weight: .semibold))
                            Text(localized("Unlocks Extended Dynamic Range headroom so standard desktop apps can reach peak XDR luminance (~%d nits).", xdrCfg.estimatedNits))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { xdrCfg.isEnabled },
                            set: { enabled in
                                manager.setXDRUpscaling(for: display, enabled: enabled, factor: enabled ? max(1.25, xdrCfg.boostFactor) : 1.0)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    if xdrCfg.isEnabled {
                        HStack(spacing: 12) {
                            Text(localized("XDR Boost Level"))
                                .font(.system(size: 12.5, weight: .medium))
                                .frame(width: 120, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { xdrCfg.boostFactor },
                                    set: { factor in
                                        manager.setXDRUpscaling(for: display, enabled: true, factor: factor)
                                    }
                                ),
                                in: 1.0...2.0
                            )

                            Text("\(xdrCfg.boostPercentage)% (~\(xdrCfg.estimatedNits) nits)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .frame(width: 145, alignment: .trailing)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(localized("ColorSync Gamma & Kelvin Temperature Calibration"))
                            .font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Button {
                            manager.resetSoftwareColor(for: display)
                        } label: {
                            Label(localized("Reset to Reference D65"), systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(localized("Color Temperature: %dK", Int(colorAdj.temperatureKelvin.rounded())))
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            HStack(spacing: 6) {
                                ForEach([3400, 5000, 6500, 7500, 9300], id: \.self) { k in
                                    Button("\(k)K") {
                                        manager.updateSoftwareColor(for: display) { $0.temperatureKelvin = Float(k) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }

                        Slider(
                            value: Binding(
                                get: { colorAdj.temperatureKelvin },
                                set: { val in
                                    manager.updateSoftwareColor(for: display) { $0.temperatureKelvin = val }
                                }
                            ),
                            in: 2700...9300,
                            step: 50
                        )
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text(localized("Red Channel"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(width: 100, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { colorAdj.redGain },
                                    set: { val in manager.updateSoftwareColor(for: display) { $0.redGain = val } }
                                ),
                                in: 0.2...1.5
                            )
                            Text("\(Int(round(colorAdj.redGain * 100)))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 45, alignment: .trailing)
                        }

                        HStack(spacing: 12) {
                            Text(localized("Green Channel"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.green)
                                .frame(width: 100, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { colorAdj.greenGain },
                                    set: { val in manager.updateSoftwareColor(for: display) { $0.greenGain = val } }
                                ),
                                in: 0.2...1.5
                            )
                            Text("\(Int(round(colorAdj.greenGain * 100)))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 45, alignment: .trailing)
                        }

                        HStack(spacing: 12) {
                            Text(localized("Blue Channel"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.blue)
                                .frame(width: 100, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { colorAdj.blueGain },
                                    set: { val in manager.updateSoftwareColor(for: display) { $0.blueGain = val } }
                                ),
                                in: 0.2...1.5
                            )
                            Text("\(Int(round(colorAdj.blueGain * 100)))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 45, alignment: .trailing)
                        }

                        HStack(spacing: 12) {
                            Text(localized("Gamma Offset"))
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 100, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { colorAdj.gammaOffset },
                                    set: { val in manager.updateSoftwareColor(for: display) { $0.gammaOffset = val } }
                                ),
                                in: -0.5...0.5
                            )
                            Text(String(format: "%+.2f", colorAdj.gammaOffset))
                                .font(.caption.monospacedDigit())
                                .frame(width: 45, alignment: .trailing)
                        }

                        HStack(spacing: 12) {
                            Text(localized("Software Contrast"))
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 100, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { colorAdj.softwareContrast },
                                    set: { val in manager.updateSoftwareColor(for: display) { $0.softwareContrast = val } }
                                ),
                                in: 0.5...1.5
                            )
                            Text("\(Int(round(colorAdj.softwareContrast * 100)))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 45, alignment: .trailing)
                        }
                    }

                    Divider()

                    HStack(spacing: 24) {
                        Toggle(
                            localized("Grayscale Filter (Monochrome)"),
                            isOn: Binding(
                                get: { colorAdj.isGrayscale },
                                set: { val in manager.updateSoftwareColor(for: display) { $0.isGrayscale = val } }
                            )
                        )
                        .font(.system(size: 12.5))
                        .toggleStyle(.checkbox)

                        Toggle(
                            localized("Invert Display Colors"),
                            isOn: Binding(
                                get: { colorAdj.isInverted },
                                set: { val in manager.updateSoftwareColor(for: display) { $0.isInverted = val } }
                            )
                        )
                        .font(.system(size: 12.5))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                )
            }
        }
    }

    private var virtualScreensSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "rectangle.on.rectangle.dashed")
                        .font(.system(size: 22))
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Virtual Screens (Dummy Displays)"))
                            .font(.headline)
                        Text(localized("Create customizable software virtual monitors for headless Macs, Sidecar iPad workspaces, streaming, or HiDPI scaling."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                HStack(spacing: 12) {
                    TextField(localized("Virtual Screen Name"), text: $newVirtualName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    Picker(localized("Aspect Ratio"), selection: $newVirtualAspect) {
                        ForEach(VirtualAspectRatio.allCases) { ratio in
                            Text(ratio.title).tag(ratio)
                        }
                    }
                    .frame(width: 260)

                    Toggle("HiDPI", isOn: $newVirtualHiDPI)
                        .toggleStyle(.checkbox)

                    Toggle(localized("Auto-Connect"), isOn: $newVirtualAutoConnect)
                        .toggleStyle(.checkbox)

                    Spacer()

                    Button {
                        let cfg = VirtualScreenConfig(
                            name: newVirtualName.isEmpty ? "MonoHub Virtual Display" : newVirtualName,
                            aspectRatio: newVirtualAspect,
                            refreshRate: newVirtualRefresh,
                            hiDPIEnabled: newVirtualHiDPI,
                            isConnected: true,
                            autoConnectOnStartup: newVirtualAutoConnect
                        )
                        var mutable = cfg
                        mutable.activeDisplayID = VirtualScreenEngine.shared.connectVirtualScreen(cfg)
                        preferences.virtualScreens.append(mutable)
                    } label: {
                        Label(localized("Create Virtual Screen"), systemImage: "plus.rectangle.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )

            if preferences.virtualScreens.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(localized("No virtual screens configured yet."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(30)
            } else {
                ForEach(preferences.virtualScreens) { vScreen in
                    let isLive = VirtualScreenEngine.shared.activeDisplayID(for: vScreen.id) != nil || vScreen.isConnected
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.on.rectangle.dashed")
                            .font(.system(size: 18))
                            .foregroundStyle(isLive ? .purple : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(vScreen.name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                Text(vScreen.aspectRatio.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.purple.opacity(0.15)))
                                    .foregroundStyle(.purple)
                                if vScreen.hiDPIEnabled {
                                    Text("HiDPI")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.mint.opacity(0.15)))
                                        .foregroundStyle(.mint)
                                }
                            }
                            Text(localized("Max Resolution: %d × %d px @ %d Hz", vScreen.maxWidth, vScreen.maxHeight, Int(vScreen.refreshRate)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            if let idx = preferences.virtualScreens.firstIndex(where: { $0.id == vScreen.id }) {
                                if isLive {
                                    VirtualScreenEngine.shared.disconnectVirtualScreen(id: vScreen.id)
                                    preferences.virtualScreens[idx].isConnected = false
                                    preferences.virtualScreens[idx].activeDisplayID = nil
                                } else {
                                    let assigned = VirtualScreenEngine.shared.connectVirtualScreen(vScreen)
                                    preferences.virtualScreens[idx].isConnected = true
                                    preferences.virtualScreens[idx].activeDisplayID = assigned
                                }
                            }
                        } label: {
                            Label(
                                isLive ? localized("Disconnect") : localized("Connect"),
                                systemImage: isLive ? "eject.fill" : "play.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            VirtualScreenEngine.shared.disconnectVirtualScreen(id: vScreen.id)
                            preferences.virtualScreens.removeAll { $0.id == vScreen.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                    )
                }
            }
        }
    }

    private var pipAndTeleprompterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "pip.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Picture-in-Picture (PiP) & Teleprompter Mirror Stream"))
                            .font(.headline)
                        Text(localized("Stream any physical or virtual display in a floating window with horizontal/vertical teleprompter flip, region cropping, and click-through."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                HStack(spacing: 14) {
                    Picker(localized("Source Display"), selection: $pipSourceDisplayID) {
                        ForEach(manager.displays) { d in
                            Text(d.name).tag(d.id)
                        }
                    }
                    .frame(width: 240)

                    Picker(localized("Orientation Flip"), selection: $pipFlipMode) {
                        ForEach(TeleprompterFlipMode.allCases) { flip in
                            Label(flip.title, systemImage: flip.systemImage).tag(flip)
                        }
                    }
                    .frame(width: 260)

                    Picker(localized("Crop Region"), selection: $pipCropPreset) {
                        ForEach(PiPCropPreset.allCases) { crop in
                            Text(crop.title).tag(crop)
                        }
                    }
                    .frame(width: 190)

                    Spacer()

                    Button {
                        let source = manager.displays.first(where: { $0.id == pipSourceDisplayID }) ?? manager.displays.first
                        guard let source else { return }
                        let cfg = PiPStreamConfig(
                            sourceDisplayID: source.id,
                            sourceName: source.name,
                            opacity: pipOpacity,
                            isClickThrough: pipClickThrough,
                            alwaysOnTop: pipAlwaysOnTop,
                            flipMode: pipFlipMode,
                            cropPreset: pipCropPreset
                        )
                        pipEngine.startPiPStream(cfg)
                    } label: {
                        Label(localized("Launch PiP Window"), systemImage: "pip.enter")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                }

                HStack(spacing: 20) {
                    Toggle(localized("Click-Through (Ignore Mouse Events)"), isOn: $pipClickThrough)
                        .font(.system(size: 12.5))
                        .toggleStyle(.checkbox)

                    Toggle(localized("Always on Top"), isOn: $pipAlwaysOnTop)
                        .font(.system(size: 12.5))
                        .toggleStyle(.checkbox)

                    HStack(spacing: 8) {
                        Text(localized("Opacity: %d%%", Int(round(pipOpacity * 100))))
                            .font(.caption)
                        Slider(value: $pipOpacity, in: 0.2...1.0)
                            .frame(width: 140)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )

            if !pipEngine.activeStreams.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(localized("Active PiP Streams (%d)", pipEngine.activeStreams.count))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(localized("Close All PiP Windows")) {
                            pipEngine.stopAllStreams()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    ForEach(pipEngine.activeStreams) { stream in
                        HStack {
                            Image(systemName: "pip")
                                .foregroundStyle(.teal)
                            Text(stream.sourceName)
                                .font(.system(size: 13, weight: .semibold))
                            Text("• \(stream.flipMode.title) • \(stream.cropPreset.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(localized("Close PiP")) {
                                pipEngine.stopPiPStream(id: stream.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                        )
                    }
                }
            }
        }
    }

    private var layoutAndEDIDSection: some View {
        let selectedDisplay = manager.displays.first(where: { $0.id == selectedDisplayIDForEDID }) ?? manager.displays.first
        let edidInfo = selectedDisplay.flatMap { manager.edidByDisplay[$0.id] }

        return VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 20))
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Multi-Monitor Layout Protection & Arrangement Anchors"))
                            .font(.headline)
                        Text(localized("Save your exact multi-monitor arrangement, origins, and HiDPI modes to prevent macOS from scrambling screen positions on wake."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(localized("Auto-Protect Layout"), isOn: $preferences.isLayoutProtectionEnabled)
                        .toggleStyle(.switch)
                }

                displayArrangementCanvas

                HStack(spacing: 10) {
                    TextField(localized("Profile Name"), text: $newLayoutAnchorName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                    Button {
                        let anchor = ResolutionAndLayoutEngine.shared.captureCurrentLayout(
                            name: newLayoutAnchorName.isEmpty ? "Saved Layout" : newLayoutAnchorName,
                            displays: manager.displays
                        )
                        preferences.savedLayoutAnchors.insert(anchor, at: 0)
                    } label: {
                        Label(localized("Save Current Arrangement"), systemImage: "lock.rectangle.stack")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .controlSize(.small)

                    Spacer()
                }

                if !preferences.savedLayoutAnchors.isEmpty {
                    ForEach(preferences.savedLayoutAnchors) { anchor in
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.cyan)
                            Text(anchor.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text(localized("(%d displays)", anchor.entries.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(localized("Restore Layout")) {
                                _ = ResolutionAndLayoutEngine.shared.restoreLayout(anchor, currentDisplays: manager.displays)
                                manager.refreshDisplays()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(role: .destructive) {
                                preferences.savedLayoutAnchors.removeAll { $0.id == anchor.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localized("Hardware EDID Inspector & Display Override Generator"))
                            .font(.headline)
                        Text(localized("Inspect VESA EDID 1.4 descriptors and export macOS Display Override plists to force Full RGB, Night Shift, and custom HiDPI modes."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !manager.displays.isEmpty {
                        Picker(localized("Display"), selection: $selectedDisplayIDForEDID) {
                            ForEach(manager.displays) { d in
                                Text(d.name).tag(d.id)
                            }
                        }
                        .frame(width: 240)
                    }
                }

                if let display = selectedDisplay, let edid = edidInfo {
                    Divider()

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        edidMetric(title: localized("Manufacturer"), value: "\(edid.manufacturerName) (\(edid.manufacturerCode))")
                        edidMetric(title: localized("Vendor / Product ID"), value: String(format: "0x%04X / 0x%04X", display.vendorNumber, edid.productCode))
                        edidMetric(title: localized("EDID Version"), value: "v\(edid.edidVersion) (\(edid.byteCount) B)")
                        edidMetric(title: localized("Video Interface"), value: "\(edid.videoInterface) • \(edid.bitDepthPerColor)-bit")
                        edidMetric(title: localized("Physical Panel Size"), value: "\(edid.horizontalSizeCm)×\(edid.verticalSizeCm) cm (\(edid.diagonalInches)\")")
                        edidMetric(title: localized("Pixel Density & Gamma"), value: "\(edid.nativePPI) PPI • γ \(String(format: "%.2f", edid.gamma))")
                        edidMetric(title: localized("Manufacture Date"), value: "W\(edid.manufactureWeek) / \(edid.manufactureYear)")
                        edidMetric(title: localized("HDR / EDR Peak"), value: "\(Int(edid.maxPotentialEDRNits)) nits")
                        edidMetric(title: localized("Checksum Status"), value: edid.checksumValid ? localized("Valid (0x00)") : localized("Modified"))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(localized("Raw EDID Hex Dump (128 Bytes)"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(edid.rawHexDump, forType: .string)
                            } label: {
                                Label(localized("Copy EDID Hex"), systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }

                        Text(edid.rawHexDump)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.black.opacity(0.25))
                            )
                    }

                    Divider()

                    HStack(spacing: 16) {
                        Toggle(localized("Force Full RGB Pixel Encoding (Fix YCbCr TV Washed Colors)"), isOn: $overrideForceRGB)
                            .font(.system(size: 12))
                            .toggleStyle(.checkbox)

                        Toggle(localized("Unlock Night Shift & True Tone"), isOn: $overrideUnlockNightShift)
                            .font(.system(size: 12))
                            .toggleStyle(.checkbox)

                        Spacer()

                        Button {
                            let cfg = preferences.config(for: display.uuid)
                            let plistXml = EDIDParser.generateOverridePlist(
                                vendorID: display.vendorNumber,
                                productID: display.modelNumber,
                                displayName: display.name,
                                forceFullRGB: overrideForceRGB,
                                unlockNightShift: overrideUnlockNightShift,
                                customResolutions: cfg.customScaledResolutions
                            )
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(plistXml, forType: .string)
                        } label: {
                            Label(localized("Copy Override Plist"), systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .controlSize(.small)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )
        }
    }

    private var displayArrangementCanvas: some View {
        HStack(spacing: 16) {
            ForEach(manager.displays) { display in
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if display.isMainDisplay {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                        }
                        Text(display.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(display.resolutionString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("(\(Int(display.origin.x)), \(Int(display.origin.y)))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 140, height: 82)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(display.isMainDisplay ? Color.cyan.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(display.isMainDisplay ? Color.cyan : Color.primary.opacity(0.2), lineWidth: 1.5)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.15))
        )
    }

    private func edidMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct FlowLayoutChips<Item: Identifiable, ChipView: View>: View {
    let items: [Item]
    @ViewBuilder let chip: (Item) -> ChipView

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                chip(item)
            }
        }
    }
}
