import SwiftUI

struct NetworkPanelView: View {
    private let engine = SystemMonitorEngine.shared

    var body: some View {
        let net = engine.networkData
        let tint = ModuleType.network.tint
        let subtitle: String = {
            guard net.isConnected else { return localized("Not Connected") }
            return [net.interfaceDisplayName, net.interfaceName].compactMap { $0 }.joined(separator: " · ")
        }()

        PanelHeader(title: localized("Network"), subtitle: subtitle, symbol: net.interfaceDisplayName == "Wi-Fi" ? "wifi" : "network", tint: tint) {
            Circle()
                .fill(net.isConnected ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
                .help(net.isConnected ? localized("Connected") : localized("Disconnected"))
        }

        HStack(spacing: 8) {
            StatTile(title: localized("Receiving"), value: Formatting.speed(net.downloadBytesPerSec), detail: localized("peak %@", Formatting.speed(net.peakDownloadBytesPerSec)), tint: .blue)
            StatTile(title: localized("Sending"), value: Formatting.speed(net.uploadBytesPerSec), detail: localized("peak %@", Formatting.speed(net.peakUploadBytesPerSec)), tint: .orange)
        }

        Platter {
            HistoryChart(series: [
                ChartSeries(values: net.downloadHistory.values, tint: .blue),
                ChartSeries(values: net.uploadHistory.values, tint: .orange)
            ])
        }

        InfoList([
            (localized("IPv4 Address"), net.localIPv4 ?? "—"),
            (localized("IPv6 Address"), net.localIPv6 ?? "—"),
            (localized("Received this session"), Formatting.storage(net.sessionInBytes)),
            (localized("Sent this session"), Formatting.storage(net.sessionOutBytes))
        ])
    }
}
