import SwiftUI
import Charts

struct BatteryHealthView: View {
    private let engine = SystemMonitorEngine.shared
    private let healthEngine = BatteryHealthEngine.shared

    var body: some View {
        let battery = engine.batteryData

        ScrollView {
            VStack(alignment: .leading, spacing: HubMetrics.sectionSpacing) {

                heroCard(battery: battery)

                healthMetricsGrid(battery: battery)

                recentEnergyConsumersCard(battery: battery)

                if !healthEngine.history.isEmpty {
                    historySection
                }

                preservationCard

                if !battery.connectedDevices.isEmpty {
                    connectedDevicesSection(devices: battery.connectedDevices)
                }
            }
            .padding(HubMetrics.pagePadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            healthEngine.recordSample(from: engine.batteryData)
        }
        .onChange(of: engine.batteryData) { _, newBattery in
            healthEngine.recordSample(from: newBattery)
        }
    }

    private func heroCard(battery: BatteryData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                HubIcon(
                    systemName: battery.hasBattery ? "battery.100percent.bolt" : "powerplug.portrait.fill",
                    tint: battery.healthPercent ?? 100 >= 80 ? .green : .orange,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(battery.hasBattery ? localized("Battery Health") : localized("Power Supply"))
                            .font(.title2.weight(.bold))
                        if battery.hasBattery {
                            Text(battery.conditionDescription)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    (battery.healthPercent ?? 100 >= 80 ? Color.green : Color.orange).opacity(0.15),
                                    in: Capsule()
                                )
                                .foregroundStyle(battery.healthPercent ?? 100 >= 80 ? Color.green : Color.orange)
                        }
                    }

                    Text(battery.stateDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if battery.hasBattery {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(battery.levelPercent)%")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(battery.level <= 0.2 && !battery.isConnectedToPower ? .red : .primary)
                            BatteryGlyph(
                                level: battery.level,
                                isCharging: battery.isCharging,
                                isConnected: battery.isConnectedToPower,
                                isLowPowerMode: battery.isLowPowerMode,
                                width: 34
                            )
                        }
                        if let health = battery.healthPercent {
                            Text(localized("Maximum Capacity: %d%%", health))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if battery.hasBattery {
                ProgressView(value: battery.level)
                    .tint(battery.level <= 0.2 && !battery.isConnectedToPower ? .red : .green)
            }
        }
        .hubCard()
    }

    private func healthMetricsGrid(battery: BatteryData) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: HubMetrics.itemSpacing)], spacing: HubMetrics.itemSpacing) {

            metricTile(
                title: localized("Maximum Capacity"),
                value: battery.healthPercent.map { "\($0)%" } ?? "—",
                detail: localized("Factory design: %@ mAh", battery.designCapacityMah.map { "\($0)" } ?? "—"),
                icon: "heart.fill",
                tint: .pink
            )

            let cycles = battery.cycleCount ?? 0
            let cycleMax = battery.designCycleCount ?? 1000
            metricTile(
                title: localized("Charge Cycles"),
                value: "\(cycles)",
                detail: localized("%d of %d recommended cycles", cycles, cycleMax),
                icon: "arrow.triangle.2.circlepath",
                tint: .blue
            )

            let temp = battery.temperatureCelsius
            metricTile(
                title: localized("Temperature"),
                value: temp.map { Formatting.temperature($0) } ?? "—",
                detail: temp.map { $0 > 40 ? localized("Elevated") : localized("Normal range") } ?? "—",
                icon: "thermometer.medium",
                tint: UsageColor.forBatteryTemperature(temp)
            )

            metricTile(
                title: battery.isCharging ? localized("Charging Power") : (battery.isACConnected ? localized("AC Power") : localized("Discharge Rate")),
                value: Formatting.watts(abs(battery.batteryPowerWatts)),
                detail: battery.powerSourceDescription,
                icon: "bolt.fill",
                tint: battery.batteryPowerWatts > 0.05 ? .green : .secondary
            )

            metricTile(
                title: localized("Full Charge Capacity"),
                value: battery.fullChargeCapacityMah.map { "\($0) mAh" } ?? "—",
                detail: localized("Design: %@ mAh", battery.designCapacityMah.map { "\($0)" } ?? "—"),
                icon: "battery.100percent",
                tint: .teal
            )

            metricTile(
                title: localized("Voltage"),
                value: battery.voltageVolts.map { "\(Formatting.decimal($0, digits: 2)) V" } ?? "—",
                detail: localized("Internal cell state"),
                icon: "gauge.with.dots.needle.50percent",
                tint: .indigo
            )
        }
    }

    private func metricTile(title: String, value: String, detail: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HubIcon(systemName: icon, tint: tint, size: 22)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .hubCard()
    }

    private func recentEnergyConsumersCard(battery: BatteryData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HubIcon(systemName: "bolt.badge.clock.fill", tint: .orange, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Recent Energy Consumers"))
                        .font(.headline)
                    Text(localized("Apps and processes consuming the most energy in recent time and what resources they use"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sysWatts = battery.systemPowerWatts {
                    Text(Formatting.watts(sysWatts))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            if battery.topProcesses.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(localized("Collecting samples…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ProcessListView(items: battery.topProcesses, metric: .energy, tint: .orange)
            }
        }
        .hubCard()
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localized("Recent Battery History"), systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text(localized("Last %d samples", healthEngine.history.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart(healthEngine.history) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Level", sample.levelPercent)
                )
                .foregroundStyle(Color.green.gradient)
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Level", sample.levelPercent)
                )
                .foregroundStyle(Color.green.opacity(0.1).gradient)
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 140)
        }
        .hubCard()
    }

    private var preservationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HubIcon(systemName: "bell.badge.fill", tint: .orange, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Battery Preservation Alerts"))
                        .font(.headline)
                    Text(localized("Receive notifications to protect and prolong battery chemical life"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            Toggle(isOn: Binding(
                get: { healthEngine.alertAt80Percent },
                set: { val in
                    healthEngine.alertAt80Percent = val
                    if val { healthEngine.requestNotificationPermission() }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Alert at 80% Charge"))
                        .font(.subheadline.weight(.medium))
                    Text(localized("Notify when battery reaches 80% while plugged in to avoid unnecessary high-voltage stress."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { healthEngine.alertAt100Percent },
                set: { val in
                    healthEngine.alertAt100Percent = val
                    if val { healthEngine.requestNotificationPermission() }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Alert at Full Charge (100%)"))
                        .font(.subheadline.weight(.medium))
                    Text(localized("Notify when battery is completely charged."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { healthEngine.alertOnHighTemp },
                set: { val in
                    healthEngine.alertOnHighTemp = val
                    if val { healthEngine.requestNotificationPermission() }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("High Temperature Warning (>42°C)"))
                        .font(.subheadline.weight(.medium))
                    Text(localized("Warn if the battery reaches elevated temperatures during charging or intensive workloads."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .hubCard()
    }

    private func connectedDevicesSection(devices: [ConnectedDeviceBattery]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(localized("Connected Bluetooth Devices"), systemImage: "wave.3.right")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: HubMetrics.itemSpacing)], spacing: HubMetrics.itemSpacing) {
                ForEach(devices) { device in
                    HStack(spacing: 12) {
                        HubIcon(systemName: device.iconName, tint: .blue, size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text("\(device.levelPercent)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProgressView(value: device.level)
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                    }
                    .hubCard(padding: 10)
                }
            }
        }
        .hubCard()
    }
}
