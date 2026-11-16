import Foundation
import SwiftUI

nonisolated enum DevEnvCategory: String, Sendable, CaseIterable, Identifiable {
    case xcode = "Xcode & Apple"
    case node = "Node.js & JS"
    case python = "Python & ML"
    case homebrew = "Homebrew"
    case rustGo = "Rust & Go"
    case containers = "Docker"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xcode: return localized("Xcode & Apple")
        case .node: return localized("Node.js & JS")
        case .python: return localized("Python & ML")
        case .homebrew: return localized("Homebrew")
        case .rustGo: return localized("Rust & Go")
        case .containers: return localized("Docker")
        }
    }

    var icon: String {
        switch self {
        case .xcode: return "hammer.fill"
        case .node: return "shippingbox.fill"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .homebrew: return "mug.fill"
        case .rustGo: return "gearshape.2.fill"
        case .containers: return "cube.box.fill"
        }
    }

    var color: Color {
        switch self {
        case .xcode: return .blue
        case .node: return .green
        case .python: return .yellow
        case .homebrew: return .orange
        case .rustGo: return .red
        case .containers: return .cyan
        }
    }
}

nonisolated struct DevEnvItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let category: DevEnvCategory
    let url: URL
    let sizeBytes: Int64
    let lastModified: Date?
    let detail: String
    let isSafeCache: Bool
    var isSelected: Bool

    init(
        id: String,
        name: String,
        category: DevEnvCategory,
        url: URL,
        sizeBytes: Int64,
        lastModified: Date? = nil,
        detail: String,
        isSafeCache: Bool,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.detail = detail
        self.isSafeCache = isSafeCache
        self.isSelected = isSelected
    }
}
