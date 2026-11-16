import Foundation
import AppKit

nonisolated struct MeetingLinkRouter: Sendable {
    static func rewriteIfSupported(url: URL, checkAppInstalled: Bool = true) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }

        if host.contains("zoom.us") && url.path.contains("/j/") {
            let components = url.path.components(separatedBy: "/j/")
            if components.count > 1, let meetingID = components[1].components(separatedBy: "/").first, !meetingID.isEmpty {
                var nativeURLString = "zoommtg://zoom.us/join?confno=\(meetingID)"
                if let query = url.query, !query.isEmpty {
                    nativeURLString += "&\(query)"
                }
                if let nativeURL = URL(string: nativeURLString) {
                    if !checkAppInstalled || isSchemeAvailable("zoommtg") {
                        return nativeURL
                    }
                }
            }
        }

        if host.contains("teams.microsoft.com") || host.contains("teams.live.com") {
            if url.path.contains("/l/meetup-join/") || url.path.contains("/meet/") {
                let fullPathWithQuery = (url.path + (url.query.map { "?\($0)" } ?? ""))
                let nativeURLString = "msteams://\(host)\(fullPathWithQuery)"
                if let nativeURL = URL(string: nativeURLString) {
                    if !checkAppInstalled || isSchemeAvailable("msteams") {
                        return nativeURL
                    }
                }
            }
        }

        if host.contains("figma.com") {
            let path = url.path
            if path.hasPrefix("/file/") || path.hasPrefix("/design/") || path.hasPrefix("/proto/") || path.hasPrefix("/board/") {
                let queryPart = url.query.map { "?\($0)" } ?? ""
                let nativeURLString = "figma://\(path.dropFirst())\(queryPart)"
                if let nativeURL = URL(string: nativeURLString) {
                    if !checkAppInstalled || isSchemeAvailable("figma") {
                        return nativeURL
                    }
                }
            }
        }

        if host.contains("notion.so") && !url.path.isEmpty && url.path != "/" {
            let cleanHost = host.replacingOccurrences(of: "www.", with: "")
            let queryPart = url.query.map { "?\($0)" } ?? ""
            let nativeURLString = "notion://\(cleanHost)\(url.path)\(queryPart)"
            if let nativeURL = URL(string: nativeURLString) {
                if !checkAppInstalled || isSchemeAvailable("notion") {
                    return nativeURL
                }
            }
        }

        if host == "t.me" || host == "telegram.me" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty && !path.contains("/") {
                let nativeURLString = "tg://resolve?domain=\(path)"
                if let nativeURL = URL(string: nativeURLString) {
                    if !checkAppInstalled || isSchemeAvailable("tg") {
                        return nativeURL
                    }
                }
            }
        }

        return nil
    }

    private static func isSchemeAvailable(_ scheme: String) -> Bool {
        guard !AppInfo.isRunningTests else { return true }
        guard let url = URL(string: "\(scheme)://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }
}
