import Foundation
import AppKit

nonisolated struct InstalledBrowser: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let bundleID: String
    let appURL: URL
    let isDefault: Bool

    init(name: String, bundleID: String, appURL: URL, isDefault: Bool = false) {
        self.id = bundleID
        self.name = name
        self.bundleID = bundleID
        self.appURL = appURL
        self.isDefault = isDefault
    }
}

nonisolated struct URLRoutingRule: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool

    var sourceAppBundleID: String?

    var sourceAppName: String?

    var domainPattern: String

    var targetBrowserBundleID: String

    var targetBrowserName: String?

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        domainPattern: String = "*",
        targetBrowserBundleID: String,
        targetBrowserName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.domainPattern = domainPattern
        self.targetBrowserBundleID = targetBrowserBundleID
        self.targetBrowserName = targetBrowserName
    }

    func matches(url: URL, sourceApp: String?) -> Bool {
        guard isEnabled else { return false }

        if let requiredSource = sourceAppBundleID, !requiredSource.isEmpty {
            guard let actualSource = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines), !actualSource.isEmpty else {
                return false
            }
            if !actualSource.localizedCaseInsensitiveContains(requiredSource) &&
               !requiredSource.localizedCaseInsensitiveContains(actualSource) {
                return false
            }
        }

        let pattern = domainPattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if pattern == "*" || pattern.isEmpty {
            return true
        }

        guard let host = url.host?.lowercased() else {
            return false
        }

        if host == pattern {
            return true
        }

        if pattern.hasPrefix("*.") {
            let base = String(pattern.dropFirst(2))
            return host == base || host.hasSuffix("." + base)
        }

        if host.hasSuffix("." + pattern) {
            return true
        }

        return false
    }
}
