import SwiftUI

struct BluetoothView: View {
    private let bluetoothManager = BluetoothManager.shared
    private let batteryManager = BatteryManager.shared
    private let preferences = NotchPreferences.shared

    @State private var filterMode: FilterMode = .all

    enum FilterMode: String, CaseIterable, Identifiable {
        case all
        case connected

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return localized("All")
            case .connected: return localized("Connected")
            }
        }
    }

    init() {}

    private var displayedDevices: [BluetoothDeviceInfo] {
        if preferences.bluetoothHideDisconnected {
            return bluetoothManager.connectedDevices
        }
        switch filterMode {
        case .all:
            return bluetoothManager.allDevices.isEmpty ? bluetoothManager.connectedDevices : bluetoothManager.allDevices
        case .connected:
            return bluetoothManager.connectedDevices
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if displayedDevices.isEmpty {
                emptyStateView
            } else {
                devicesGrid
            }
        }
        .notchModule()
        .task {
            bluetoothManager.refreshDevices(includeProfiler: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                bluetoothManager.refreshDevices()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                NotchSectionLabel(localized("Bluetooth"), systemImage: "antenna.radiowaves.left.and.right", tint: .indigo)

                if !bluetoothManager.connectedDevices.isEmpty {
                    let count = bluetoothManager.connectedDevices.count
                    Text(count == 1 ? localized("1 active") : String(format: localized("%d active"), count))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                }
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(FilterMode.allCases) { mode in
                    let isSelected = filterMode == mode
                    Button {
                        NotchHaptics.tap()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            filterMode = mode
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background(
                                Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.09))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if preferences.bluetoothShowMacBattery && batteryManager.isMonitoring {
                let sysBattery = batteryManager.batteryInfo
                HStack(spacing: 4) {
                    Image(systemName: sysBattery.isCharging ? "bolt.fill" : "laptopcomputer")
                        .font(.system(size: 9))
                        .foregroundStyle(sysBattery.isCharging ? .green : NotchTheme.secondaryText)

                    Text(String(format: localized("Mac: %d%%"), sysBattery.percentage))
                        .font(NotchTheme.monoDigits)
                        .foregroundStyle(NotchTheme.secondaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Button {
                NotchHaptics.tap()
                bluetoothManager.refreshDevices(includeProfiler: true, force: true)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: bluetoothManager.isScanning)
                    Text(localized("Refresh"))
                }
            }
            .buttonStyle(NotchSecondaryButtonStyle())
        }
    }

    private var devicesGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(displayedDevices) { device in
                    deviceCard(device)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func deviceCard(_ device: BluetoothDeviceInfo) -> some View {
        let accent = categoryColor(for: device.category)

        VStack(alignment: .leading, spacing: 6) {

            HStack(spacing: 7) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(accent.opacity(device.isConnected ? 0.45 : 0.15), lineWidth: 1)
                        )

                    Image(systemName: device.category.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)

                    Circle()
                        .fill(device.isConnected ? Color.green : Color.gray.opacity(0.6))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.2))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        Text(device.isConnected ? localized("Connected") : localized("Paired"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(device.isConnected ? Color.green : NotchTheme.tertiaryText)

                        if let vendor = device.vendorName {
                            Text("• \(vendor)")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(NotchTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                if let primaryBat = device.primaryBattery {
                    topBatteryBadge(level: primaryBat, isCharging: device.isCharging, isLow: device.isLowBattery)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 4) {
                if device.hasMultiPartBattery && (device.batteryLeftLevel != nil || device.batteryRightLevel != nil || device.batteryCaseLevel != nil) {
                    HStack(spacing: 4) {
                        if let left = device.batteryLeftLevel {
                            miniBatteryPill(label: localized("L"), value: left, isCharging: device.isCharging)
                        }
                        if let right = device.batteryRightLevel {
                            miniBatteryPill(label: localized("R"), value: right, isCharging: device.isCharging)
                        }
                        if let c = device.batteryCaseLevel {
                            miniBatteryPill(label: localized("Case"), value: c, isCharging: false)
                        }
                    }
                } else if let battery = device.primaryBattery {
                    HStack(spacing: 6) {
                        NotchProgressBar(
                            progress: Double(battery) / 100.0,
                            tint: batteryColor(level: battery, isCharging: device.isCharging),
                            height: 4
                        )

                        Text(device.isCharging ? localized("Charging") : (device.isLowBattery ? localized("Low") : localized("Battery")))
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(device.isLowBattery ? Color.red : NotchTheme.secondaryText)
                    }
                }

                HStack(spacing: 4) {
                    metadataChip(icon: device.category.iconName, text: device.category.localizedName)

                    if let transport = device.transportType {
                        metadataChip(icon: "dot.radiowaves.right", text: transport)
                    }

                    if let rssi = device.rssi {
                        metadataChip(icon: "cellularbars", text: "\(rssi) dBm")
                    }

                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 6) {
                Button {
                    NotchHaptics.tap()
                    bluetoothManager.toggleConnection(for: device)
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: device.isConnected ? "xmark.circle" : "bolt.horizontal.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(device.isConnected ? localized("Disconnect") : localized("Connect"))
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(device.isConnected ? Color.white.opacity(0.88) : Color.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule().fill(device.isConnected ? Color.white.opacity(0.13) : Color.white)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                let isFav = (BluetoothQuickConnectManager.shared.favoriteDeviceAddress == device.address)
                Button {
                    NotchHaptics.tap()
                    if isFav {
                        BluetoothQuickConnectManager.shared.clearFavoriteDevice()
                    } else {
                        BluetoothQuickConnectManager.shared.setFavoriteDevice(device)
                    }
                } label: {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(isFav ? Color.yellow : NotchTheme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help(localized("Set as global shortcut device ⌥ B"))

                Spacer()

                if let fw = device.firmwareVersion {
                    Text("v\(fw)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 205)
        .padding(8)
        .notchCardSurface()
    }

    @ViewBuilder
    private func topBatteryBadge(level: Int, isCharging: Bool, isLow: Bool) -> some View {
        let color = batteryColor(level: level, isCharging: isCharging)
        HStack(spacing: 2.5) {
            Image(systemName: isCharging ? "bolt.fill" : batterySymbol(for: level))
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(color)

            Text("\(level)%")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isLow ? Color.red : Color.white)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(color.opacity(0.16))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.35), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func miniBatteryPill(label: String, value: Int, isCharging: Bool) -> some View {
        let color = batteryColor(level: value, isCharging: isCharging)
        HStack(spacing: 2.5) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(NotchTheme.secondaryText)

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.green)
            }

            Text("\(value)%")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(value <= 20 ? Color.red : Color.white)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color.opacity(0.14))
        )
    }

    @ViewBuilder
    private func metadataChip(icon: String, text: String) -> some View {
        HStack(spacing: 2.5) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .semibold))
            Text(text)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(NotchTheme.secondaryText)
        .padding(.horizontal, 4.5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func batteryColor(level: Int, isCharging: Bool) -> Color {
        if isCharging { return .green }
        if level <= 20 { return .red }
        if level <= 35 { return .orange }
        return .green
    }

    private func batterySymbol(for level: Int) -> String {
        switch level {
        case 0...12: return "battery.0"
        case 13...37: return "battery.25"
        case 38...62: return "battery.50"
        case 63...87: return "battery.75"
        default: return "battery.100"
        }
    }

    private func categoryColor(for category: BluetoothDeviceCategory) -> Color {
        switch category {
        case .airpods, .headphones: return .green
        case .mouse, .trackpad: return .blue
        case .keyboard: return .indigo
        case .gamepad: return .purple
        case .phone: return .cyan
        case .watch: return .orange
        case .speaker, .display: return .yellow
        case .generic: return .gray
        }
    }

    private var emptyStateView: some View {
        NotchEmptyState(
            systemImage: "antenna.radiowaves.left.and.right",
            tint: .indigo,
            title: filterMode == .connected ? localized("No connected accessories") : localized("No paired Bluetooth devices"),
            message: filterMode == .connected
                ? localized("Connect headphones, keyboards, mice, or controllers via macOS Bluetooth menu.")
                : localized("Pair new devices in System Settings > Bluetooth.")
        )
    }
}
