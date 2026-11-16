import Foundation
import Synchronization

nonisolated enum Formatting {
    private nonisolated(unsafe) static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useAll]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let cachedDateFormatter = Mutex(DateFormatter())
    private static let cachedRelativeFormatter = Mutex(RelativeDateTimeFormatter())

    static func bytes(_ bytes: Int64) -> String {
        byteCountFormatter.string(fromByteCount: bytes)
    }

    static func bytes(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory).locale(Localization.locale))
    }

    static func storage(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .file).locale(Localization.locale))
    }

    static func date(_ date: Date) -> String {
        cachedDateFormatter.withLock { formatter in
            if formatter.locale != Localization.locale {
                formatter.locale = Localization.locale
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
            }
            return formatter.string(from: date)
        }
    }

    static func relativeDate(_ date: Date) -> String {
        cachedRelativeFormatter.withLock { formatter in
            if formatter.locale != Localization.locale {
                formatter.locale = Localization.locale
                formatter.unitsStyle = .full
            }
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }

    static func percentage(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100.0)
    }

    static func speed(_ bytesPerSecond: UInt64) -> String {
        let kilobytes = Double(bytesPerSecond) / 1_000
        if kilobytes < 1_000 {
            return "\(decimal(kilobytes, digits: kilobytes < 10 && kilobytes > 0 ? 1 : 0)) KB/s"
        }
        let megabytes = kilobytes / 1_000
        if megabytes < 1_000 {
            return "\(decimal(megabytes, digits: 1)) MB/s"
        }
        return "\(decimal(megabytes / 1_000, digits: 2)) GB/s"
    }

    static func percent(_ ratio: Double) -> String {
        "\(Int((min(max(ratio, 0), 1) * 100).rounded()))%"
    }

    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return mins > 0 ? "\(hours) h \(mins) min" : "\(hours) h"
        }
        return "\(mins) min"
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 {
            return "\(days) d \(hours) h"
        }
        if hours > 0 {
            return "\(hours) h \(minutes) min"
        }
        return "\(minutes) min"
    }

    static func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        return "\(Int(celsius.rounded()))°C"
    }

    static func watts(_ value: Double) -> String {
        "\(decimal(abs(value), digits: 1)) W"
    }

    static func decimal(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(Localization.locale))
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(Localization.locale))
    }

    static func compactSpeed(_ bytesPerSecond: UInt64) -> String {
        let kb = Double(bytesPerSecond) / 1_000.0
        if kb < 1 { return "0K" }
        if kb < 1_000 { return "\(Int(kb.rounded()))K" }
        let mb = kb / 1_000.0
        if mb < 10 { return "\(decimal(mb, digits: 1))M" }
        if mb < 1_000 { return "\(Int(mb.rounded()))M" }
        return "\(decimal(mb / 1_000.0, digits: 1))G"
    }
}

nonisolated struct RollingHistory: Sendable, Equatable {
    let capacity: Int
    private(set) var values: [Double]

    init(capacity: Int = 60) {
        self.capacity = capacity
        self.values = []
        self.values.reserveCapacity(capacity)
    }

    mutating func append(_ value: Double) {
        if values.count == capacity {
            values.removeFirst()
        }
        values.append(value)
    }

    var peak: Double {
        values.max() ?? 0
    }
}
