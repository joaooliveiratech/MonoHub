import Foundation

nonisolated enum ModuleType: String, CaseIterable, Identifiable, Codable, Sendable {
    case cpu = "cpu"
    case ram = "ram"
    case gpu = "gpu"
    case disk = "disk"
    case network = "network"
    case battery = "battery"
    case sensors = "sensors"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return localized("Processor")
        case .ram: return localized("Memory")
        case .gpu: return localized("Graphics")
        case .disk: return localized("Storage")
        case .network: return localized("Network")
        case .battery: return localized("Battery")
        case .sensors: return localized("Temperature")
        }
    }

    var shortTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .ram: return "RAM"
        case .gpu: return "GPU"
        case .disk: return "SSD"
        case .network: return "NET"
        case .battery: return "BAT"
        case .sensors: return "SOC"
        }
    }

    var sfSymbol: String {
        switch self {
        case .cpu: return "cpu"
        case .ram: return "memorychip"
        case .gpu: return "cube.transparent"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .battery: return "battery.75percent"
        case .sensors: return "thermometer.medium"
        }
    }

    var defaultOrder: Int {
        switch self {
        case .cpu: return 0
        case .ram: return 1
        case .gpu: return 2
        case .disk: return 3
        case .network: return 4
        case .battery: return 5
        case .sensors: return 6
        }
    }

    var defaultStyle: DisplayStyle {
        switch self {
        case .cpu, .ram, .gpu, .disk, .network, .battery: return .combined
        case .sensors: return .icon
        }
    }

    var availableStyles: [DisplayStyle] {
        switch self {
        case .battery:
            return [.combined, .batteryInside, .icon, .symbolStacked, .stacked, .text, .bar]
        case .network:
            return [.combined, .icon]
        case .sensors:
            return [.icon, .symbolStacked, .stacked, .text]
        case .cpu, .ram, .gpu, .disk:
            return [.combined, .stacked, .icon, .symbolStacked, .bar, .text]
        }
    }

    var usesProcessList: Bool {
        switch self {
        case .cpu, .ram, .gpu: return true
        case .disk, .network, .battery, .sensors: return false
        }
    }
}

nonisolated enum DisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case combined = "combined"
    case stacked = "stacked"
    case icon = "icon"
    case bar = "bar"
    case text = "text"
    case batteryInside = "battery_inside"
    case symbolStacked = "symbol_stacked"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: return localized("Gauge and Name")
        case .stacked: return localized("Two Lines")
        case .icon: return localized("Symbol and Value")
        case .bar: return localized("Gauge and Value")
        case .text: return localized("Text Only")
        case .batteryInside: return localized("Percentage Inside Battery")
        case .symbolStacked: return localized("Symbol over Value")
        }
    }

    func title(for module: ModuleType) -> String {
        switch (module, self) {
        case (.battery, .combined): return localized("Percentage and Icon")
        case (.battery, .icon): return localized("Icon Only")
        case (.battery, .symbolStacked): return localized("Icon over Percentage")
        case (.network, .combined): return localized("Upload and Download")
        case (.network, .icon): return localized("Dominant Traffic")
        default: return title
        }
    }

    var sfSymbol: String {
        switch self {
        case .combined: return "chart.bar.xaxis"
        case .stacked: return "text.alignleft"
        case .icon: return "square.grid.2x2"
        case .bar: return "chart.bar.fill"
        case .text: return "textformat"
        case .batteryInside: return "battery.100percent"
        case .symbolStacked: return "rectangle.split.1x2"
        }
    }
}
