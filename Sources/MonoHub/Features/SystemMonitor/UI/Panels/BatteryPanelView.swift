import SwiftUI

struct BatteryPanelView: View {
    private let engine = SystemMonitorEngine.shared
    private let prefs = MonitorPreferences.shared

    var body: some View {
        let battery = engine.batteryData
        let chargeLimit = battery.policies?.chargeLimitPercent.map { Double($0) / 100 }

        PanelHeader(title: localized("Battery"), subtitle: battery.stateTitle, symbol: headerSymbol(battery), tint: .green) {
            HStack(spacing: 8) {
                HeroValue(value: "\(battery.levelPercent)%", tint: battery.level <= 0.2 && !battery.isConnectedToPower ? .red : .primary)
                BatteryGlyph(
                    level: battery.level,
                    isCharging: battery.isCharging,
                    isConnected: battery.isConnectedToPower,
                    isLowPowerMode: battery.isLowPowerMode,
                    width: 32
                )
            }
        }

        if battery.hasBattery {
            Platter {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: battery.powerState.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(stateTint(battery.powerState))
                            .frame(width: 16)
                        Text(battery.stateDetail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    ChargeLevelBar(level: battery.level, limit: chargeLimit, tint: levelTint(battery))
                }
            }
        }

        HStack(spacing: 8) {
            StatTile(
                title: localized("Mac Power Draw"),
                value: battery.systemPowerWatts.map(Formatting.watts) ?? "—",
                detail: battery.isACConnected ? localized("from the outlet") : localized("from the battery"),
                tint: .orange
            )
            StatTile(
                title: batteryFlowTitle(battery),
                value: battery.hasBattery ? Formatting.watts(battery.batteryPowerWatts) : "—",
                detail: batteryFlowDetail(battery),
                tint: battery.batteryPowerWatts > 0.05 ? .green : .secondary
            )
        }

        TopProcessesSection(
            items: battery.topProcesses,
            metric: .energy,
            tint: .orange,
            isEnabled: prefs.showTopProcessesBattery && prefs.topProcessesCount > 0,
            customTitle: localized("Recent Energy Consumers")
        )

        if let policies = battery.policies {
            PanelSection(title: localized("Energy Mode")) {
                Text(battery.isACConnected ? localized("on power adapter") : localized("on battery"))
            } content: {
                VStack(spacing: 8) {
                    EnergyModeSelector(current: battery.activeEnergyMode ?? .automatic, supportsHighPower: policies.supportsHighPower)
                    InfoList(chargingRows(battery, policies: policies))
                }
            }
        }

        if battery.hasBattery {
            PanelSection(title: localized("Health")) {
                InfoList(tinted: [
                    (localized("Condition"), battery.conditionDescription, (battery.healthPercent ?? 100) >= 80 ? .primary : .orange),
                    (localized("Maximum Capacity"), battery.healthPercent.map { "\($0)%" } ?? "—", .primary),
                    (localized("Capacity"), capacityText(battery), .primary),
                    (localized("Cycles"), cycleText(battery), .primary),
                    (localized("Temperature"), Formatting.temperature(battery.temperatureCelsius), UsageColor.forBatteryTemperature(battery.temperatureCelsius)),
                    (localized("Voltage"), battery.voltageVolts.map { "\(Formatting.decimal($0, digits: 2)) V" } ?? "—", .primary)
                ])
            }
        }

        if !battery.connectedDevices.isEmpty {
            PanelSection(title: localized("Devices")) {
                Platter(padding: 6) {
                    ForEach(battery.connectedDevices) { device in
                        AccessoryRow(device: device)
                    }
                }
            }
        }
    }

    private func chargingRows(_ battery: BatteryData, policies: PowerPolicies) -> [(String, String)] {
        var rows: [(String, String)] = [(localized("Power Source"), battery.powerSourceDescription)]
        if battery.hasBattery {
            rows.append((localized("Charge Limit"), battery.chargeLimitDescription))
            if battery.isACConnected {
                rows.append((localized("On Battery"), policies.energyModeOnBattery.title))
            } else {
                rows.append((localized("On Power Adapter"), policies.energyModeOnAdapter.title))
            }
        }
        return rows
    }

    private func batteryFlowTitle(_ battery: BatteryData) -> String {
        if abs(battery.batteryPowerWatts) < 0.05 { return localized("Battery") }
        return battery.batteryPowerWatts > 0 ? localized("Charging Battery") : localized("Draining Battery")
    }

    private func batteryFlowDetail(_ battery: BatteryData) -> String {
        guard battery.hasBattery else { return localized("no battery") }
        if abs(battery.batteryPowerWatts) < 0.05 { return localized("no power flow") }
        return battery.batteryPowerWatts > 0 ? localized("in") : localized("out")
    }

    private func headerSymbol(_ battery: BatteryData) -> String {
        switch battery.powerState {
        case .charging: return "bolt.fill"
        case .chargingPaused, .fullyCharged, .acPowerOnly: return "powerplug.portrait.fill"
        case .discharging: return "battery.75percent"
        }
    }

    private func levelTint(_ battery: BatteryData) -> Color {
        if battery.isCharging { return .green }
        if battery.isLowPowerMode { return .yellow }
        if !battery.isConnectedToPower, battery.level <= 0.2 { return .red }
        return .primary.opacity(0.75)
    }

    private func capacityText(_ battery: BatteryData) -> String {
        guard let full = battery.fullChargeCapacityMah else { return "—" }
        if let design = battery.designCapacityMah {
            return localized("%@ of %@ mAh", Formatting.integer(full), Formatting.integer(design))
        }
        return "\(Formatting.integer(full)) mAh"
    }

    private func cycleText(_ battery: BatteryData) -> String {
        guard let cycles = battery.cycleCount else { return "—" }
        if let design = battery.designCycleCount {
            return localized("%d of %d", cycles, design)
        }
        return "\(cycles)"
    }

    private func stateTint(_ state: BatteryPowerState) -> Color {
        switch state {
        case .discharging: return .secondary
        case .charging, .fullyCharged: return .green
        case .chargingPaused: return .yellow
        case .acPowerOnly: return .blue
        }
    }
}

private struct ChargeLevelBar: View {
    let level: Double
    let limit: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(width * min(max(level, 0), 1), 6))
                    if let limit, limit < 1 {
                        Capsule()
                            .fill(Color.primary.opacity(0.6))
                            .frame(width: 2, height: 10)
                            .offset(x: width * limit - 1)
                    }
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 10)
            .animation(.smooth(duration: 0.35), value: level)

            if let limit, limit < 1 {
                GeometryReader { proxy in
                    Text(localized("Limit %d%%", Int((limit * 100).rounded())))
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: min(max(proxy.size.width * limit, 26), proxy.size.width - 26), y: proxy.size.height / 2)
                }
                .frame(height: 11)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(localized("Battery level %d%%", Int((level * 100).rounded())))
    }
}

private struct EnergyModeSelector: View {
    let current: EnergyMode
    let supportsHighPower: Bool

    private var modes: [EnergyMode] {
        supportsHighPower ? [.lowPower, .automatic, .highPower] : [.lowPower, .automatic]
    }

    var body: some View {
        Button {
            StatusItemController.shared.closePanel(animated: true)
            NativeAppLauncher.openSystemTool(for: .battery)
        } label: {
            HStack(spacing: 3) {
                ForEach(modes, id: \.self) { mode in
                    segment(mode)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(localized("Energy Mode is changed in Battery Settings"))
        .accessibilityLabel(localized("Energy Mode: %@", current.title))
        .accessibilityHint(localized("Opens Battery Settings"))
    }

    private func segment(_ mode: EnergyMode) -> some View {
        let isSelected = mode == current
        return VStack(spacing: 3) {
            Image(systemName: mode.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? tint(for: mode) : .secondary)
            Text(mode.title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
            }
        }
    }

    private func tint(for mode: EnergyMode) -> Color {
        switch mode {
        case .lowPower: return .yellow
        case .automatic: return .blue
        case .highPower: return .orange
        }
    }
}

private struct AccessoryRow: View {
    let device: ConnectedDeviceBattery

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.iconName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                if device.hasComponents {
                    HStack(spacing: 8) {
                        component(localized("L"), device.leftPercent)
                        component(localized("R"), device.rightPercent)
                        component(localized("Case"), device.casePercent)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            Text("\(device.levelPercent)%")
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(device.level <= 0.2 ? .red : .secondary)
            BatteryGlyph(level: device.level, isCharging: false, isConnected: false, width: 22)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func component(_ title: String, _ percent: Int?) -> some View {
        if let percent {
            Text("\(title) \(percent)%")
                .monospacedDigit()
        }
    }
}
