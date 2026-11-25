import SwiftUI
import AppKit

enum PortFilterType: String, CaseIterable, Identifiable {
    case listening = "Escuta (LISTEN)"
    case established = "Ativas"
    case activeTraffic = "Com Tráfego"
    case all = "Todas"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: return localized("Listening (LISTEN)")
        case .established: return localized("Active Connections")
        case .activeTraffic: return localized("Active Traffic")
        case .all: return localized("All")
        }
    }
}

enum PortSortOption: String, CaseIterable, Identifiable {
    case bandwidth = "Maior Consumo"
    case port = "Porta"
    case process = "Processo"
    case pid = "PID"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bandwidth: return localized("Bandwidth (Highest)")
        case .port: return localized("Port")
        case .process: return localized("Process")
        case .pid: return localized("Process ID (PID)")
        }
    }
}

struct PortsView: View {
    @State private var items: [NetworkPortItem] = []
    @State private var currentSnapshot: BandwidthSnapshot = .empty
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var filterType: PortFilterType = .all
    @State private var sortOption: PortSortOption = .bandwidth
    @State private var processToTerminate: NetworkPortItem?
    @State private var showTerminateConfirmation = false

    private let engine = PortsEngine.shared

    private var filteredItems: [NetworkPortItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()

        let filtered = items.filter { item in

            switch filterType {
            case .listening:
                guard item.isListening else { return false }
            case .established:
                guard item.state == "ESTABLISHED" else { return false }
            case .activeTraffic:
                guard item.hasTraffic else { return false }
            case .all:
                break
            }

            guard !query.isEmpty else { return true }
            return "\(item.port)".contains(query)
                || item.processName.lowercased().contains(query)
                || "\(item.pid)".contains(query)
                || item.localAddress.lowercased().contains(query)
                || (item.remoteAddress?.lowercased().contains(query) ?? false)
        }

        return filtered.sorted { a, b in
            switch sortOption {
            case .bandwidth:
                if a.totalSpeed != b.totalSpeed {
                    return a.totalSpeed > b.totalSpeed
                }
                let aTotal = a.totalBytesDownloaded &+ a.totalBytesUploaded
                let bTotal = b.totalBytesDownloaded &+ b.totalBytesUploaded
                if aTotal != bTotal {
                    return aTotal > bTotal
                }
                if a.isListening != b.isListening {
                    return a.isListening && !b.isListening
                }
                return a.port < b.port
            case .port:
                if a.port != b.port {
                    return a.port < b.port
                }
                return a.processName < b.processName
            case .process:
                let comp = a.processName.localizedCaseInsensitiveCompare(b.processName)
                if comp != .orderedSame {
                    return comp == .orderedAscending
                }
                return a.port < b.port
            case .pid:
                if a.pid != b.pid {
                    return a.pid < b.pid
                }
                return a.port < b.port
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSummary
            Divider()

            if isLoading && items.isEmpty {
                ProgressView(localized("Scanning network ports…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                emptyStateView
            } else {
                portsTable
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker(localized("Filter"), selection: $filterType) {
                    ForEach(PortFilterType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker(localized("Sort by"), selection: $sortOption) {
                        ForEach(PortSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(sortOption.title, systemImage: "arrow.up.arrow.down")
                }
                .help(localized("Sort by"))
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await reload() }
                } label: {
                    Label(localized("Refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                .help(localized("Refresh ports and processes"))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: localized("Search port, process or PID"))
        .task {
            await reload()

            while !Task.isCancelled {
                let pollSeconds: Double = ProcessInfo.processInfo.isLowPowerModeEnabled ? 4 : 2
                try? await Task.sleep(for: .seconds(pollSeconds))
                guard !Task.isCancelled else { break }
                let snapshot = await engine.sampleBandwidth()
                self.currentSnapshot = snapshot
                self.items = self.engine.updateBandwidth(for: self.items)
            }
        }
        .onDisappear {
            ProcessBandwidthEngine.shared.stop()
        }
        .confirmationDialog(
            processToTerminate.map { localized("Terminate process “%@” (PID %d)?", $0.processName, $0.pid) } ?? "",
            isPresented: $showTerminateConfirmation,
            titleVisibility: .visible
        ) {
            if let target = processToTerminate {
                Button(localized("Terminate (SIGTERM)"), role: .destructive) {
                    Task {
                        _ = await engine.terminateProcess(pid: target.pid, force: false)
                        await reload()
                    }
                }
                Button(localized("Force Quit (SIGKILL)"), role: .destructive) {
                    Task {
                        _ = await engine.terminateProcess(pid: target.pid, force: true)
                        await reload()
                    }
                }
                Button(localized("Cancel"), role: .cancel) {}
            }
        } message: {
            if let target = processToTerminate {
                Text(localized("The process is using port :%d. Any unsaved data in this application may be lost.", target.port))
            }
        }
    }

    private var headerSummary: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                HubIcon(systemName: "network", tint: .teal, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Network Ports & Processes"))
                        .font(.headline)
                    Text(localized("%d processes listening, %d connections active", items.filter(\.isListening).count, items.filter { $0.state == "ESTABLISHED" }.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {

                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 13))
                    Text(Formatting.speed(currentSnapshot.totalDownloadSpeed))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.1), in: Capsule())
                .help(localized("Total Real-Time Download Rate"))

                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 13))
                    Text(Formatting.speed(currentSnapshot.totalUploadSpeed))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.1), in: Capsule())
                .help(localized("Total Real-Time Upload Rate"))

                if let topName = currentSnapshot.topConsumerName, currentSnapshot.topConsumerSpeed > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 10))
                        Text(localized("Top: %@ (%@)", topName, Formatting.speed(currentSnapshot.topConsumerSpeed)))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.background.secondary, in: Capsule())
                    .help(localized("Process consuming the most bandwidth"))
                }

                if let topWeb = items.first(where: { $0.isListening && $0.isWebPort }) {
                    HStack(spacing: 6) {
                        Text(localized("Active Dev Port: :%d (%@)", topWeb.port, topWeb.processName))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let url = topWeb.webURL {
                            Link(destination: url) {
                                Label(localized("Open"), systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.background.secondary, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var portsTable: some View {
        Table(filteredItems) {
            TableColumn(localized("Process")) { item in
                HStack(spacing: 10) {
                    Image(nsImage: item.icon())
                        .resizable()
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(item.processName)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                            if item.pid == currentSnapshot.topConsumerPID && currentSnapshot.topConsumerSpeed > 0 {
                                Text("TOP")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        Text("PID \(item.pid) · \(item.user)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 180, ideal: 230)

            TableColumn(localized("Bandwidth")) { item in
                HStack(spacing: 8) {
                    if item.hasTraffic {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if item.downloadBytesPerSec > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 8.5, weight: .bold))
                                        Text(Formatting.speed(item.downloadBytesPerSec))
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    }
                                    .foregroundStyle(.blue)
                                }
                                if item.uploadBytesPerSec > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.up")
                                            .font(.system(size: 8.5, weight: .bold))
                                        Text(Formatting.speed(item.uploadBytesPerSec))
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    }
                                    .foregroundStyle(.orange)
                                }
                            }
                            if item.totalBytesDownloaded > 0 || item.totalBytesUploaded > 0 {
                                Text(localized("Total: %@", Formatting.storage(item.totalBytesDownloaded &+ item.totalBytesUploaded)))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } else if item.totalBytesDownloaded > 0 || item.totalBytesUploaded > 0 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("0 B/s")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(localized("Total: %@", Formatting.storage(item.totalBytesDownloaded &+ item.totalBytesUploaded)))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .width(min: 130, ideal: 155)

            TableColumn(localized("Port")) { item in
                HStack(spacing: 6) {
                    Text(":\(item.port)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text(item.networkProtocol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .width(min: 85, ideal: 100)

            TableColumn(localized("State")) { item in
                stateBadge(item.state)
            }
            .width(min: 90, ideal: 105)

            TableColumn(localized("Local Address")) { item in
                Text(item.localAddress)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)

            TableColumn(localized("Remote Address")) { item in
                Text(item.remoteAddress ?? "—")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)

            TableColumn(localized("Actions")) { item in
                HStack(spacing: 8) {
                    if let url = item.webURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help(localized("Open in browser: %@", url.absoluteString))
                    }

                    Button {
                        processToTerminate = item
                        showTerminateConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help(localized("Terminate process…"))
                }
            }
            .width(60)
        }
    }

    private func stateBadge(_ state: String) -> some View {
        let (color, text): (Color, String) = {
            switch state {
            case "LISTEN": return (.green, "LISTEN")
            case "ESTABLISHED": return (.blue, "ESTABLISHED")
            case "UDP": return (.purple, "UDP")
            default: return (.secondary, state)
            }
        }()

        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            localized("No Ports Found"),
            systemImage: "network.slash",
            description: Text(localized("No network processes match the current filter or search criteria."))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() async {
        isLoading = true
        _ = await engine.sampleBandwidth()
        let scanned = await engine.scanPorts()
        let snapshot = engine.latestBandwidthSnapshot()
        await MainActor.run {
            self.items = scanned
            self.currentSnapshot = snapshot
            self.isLoading = false
        }
    }
}
