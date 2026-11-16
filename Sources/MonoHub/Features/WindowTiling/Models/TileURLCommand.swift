import Foundation

enum TileURLCommand: Equatable, Sendable {
    case perform(WindowAction)
    case settings

    static let primaryScheme = "monohub"
    static let legacyScheme = "monotile"

    init?(name: String) {
        let normalized = name.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
        if normalized == "settings" || normalized.isEmpty {
            self = .settings
        } else if let action = WindowAction(commandName: normalized) {
            self = .perform(action)
        } else {
            return nil
        }
    }

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased() else { return nil }

        if scheme == Self.legacyScheme {
            let name = url.host(percentEncoded: false) ?? url.path(percentEncoded: false)
            guard name.count <= 64 else { return nil }
            self.init(name: name)
        } else if scheme == Self.primaryScheme {
            let host = url.host(percentEncoded: false)?.lowercased() ?? ""
            let path = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()

            if host == "tile" || host == "tiling" || host == "monotile" {
                if path.isEmpty || path == "settings" {
                    self = .settings
                } else if let action = WindowAction(commandName: path) {
                    self = .perform(action)
                } else {
                    return nil
                }
            } else if host == "settings" && (path.isEmpty || path == "tile") {
                self = .settings
            } else if let action = WindowAction(commandName: host) {
                self = .perform(action)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    var name: String {
        switch self {
        case .perform(let action): return action.commandName
        case .settings: return "settings"
        }
    }

    var url: URL {
        URL(string: "\(Self.legacyScheme)://\(name)")!
    }
}
