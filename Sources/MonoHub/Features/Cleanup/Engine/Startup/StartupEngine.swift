import Darwin
import Foundation

nonisolated final class StartupEngine: Sendable {
    static let shared = StartupEngine()

    private init() {}

    private static var userLaunchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private static var systemLaunchAgentsDir: URL {
        URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)
    }

    private static var systemLaunchDaemonsDir: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
    }

    func scanItems() async -> [StartupItem] {
        var allItems: [StartupItem] = []

        let loginItems = await Self.scanLoginItems()
        allItems += loginItems
        allItems += Self.scanDirectory(Self.userLaunchAgentsDir, type: .userAgent)
        allItems += Self.scanDirectory(Self.systemLaunchAgentsDir, type: .systemAgent)
        allItems += Self.scanDirectory(Self.systemLaunchDaemonsDir, type: .systemDaemon)

        return allItems.sorted {
            if $0.type.sortPriority != $1.type.sortPriority {
                return $0.type.sortPriority < $1.type.sortPriority
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func scanLoginItems() async -> [StartupItem] {
        let script = """
        tell application "System Events"
            set out to {}
            repeat with i in every login item
                set itemPath to ""
                set itemHidden to false
                try
                    set itemPath to path of i
                end try
                try
                    set itemHidden to hidden of i
                end try
                set end of out to (name of i) & "|||" & itemPath & "|||" & (itemHidden as text)
            end repeat
            set AppleScript's text item delimiters to linefeed
            return out as text
        end tell
        """

        guard let proc = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: .seconds(15)),
              proc.succeeded,
              !proc.output.isEmpty else {
            return []
        }
        let output = proc.output

        var results: [StartupItem] = []
        let lines = output.components(separatedBy: .newlines)
        let fm = FileManager.default

        for line in lines {
            let parts = line.components(separatedBy: "|||")
            guard parts.count >= 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            var rawPath = parts[1].trimmingCharacters(in: .whitespaces)
            if rawPath == "missing value" { rawPath = "" }

            var resolvedPath: String? = rawPath.isEmpty ? nil : rawPath
            if resolvedPath == nil {
                let candidates = [
                    "/Applications/\(name).app",
                    "\(fm.homeDirectoryForCurrentUser.path)/Applications/\(name).app"
                ]
                resolvedPath = candidates.first { fm.fileExists(atPath: $0) }
            }

            let exists = resolvedPath != nil && fm.fileExists(atPath: resolvedPath!)
            let isOrphaned = !exists

            var size: Int64 = 0
            if let resolved = resolvedPath, exists {
                let url = URL(fileURLWithPath: resolved)
                size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                if size == 0 {
                    size = (try? fm.attributesOfItem(atPath: resolved)[.size] as? NSNumber)?.int64Value ?? 0
                }
            }

            let isApple = name.lowercased().hasPrefix("apple") || (resolvedPath?.contains("/System/") ?? false)

            results.append(StartupItem(
                id: "loginitem:\(name)",
                name: name,
                label: "com.apple.loginitem.\(name)",
                type: .loginItem,
                plistURL: nil,
                executablePath: resolvedPath,
                arguments: [],
                isEnabled: true,
                runAtLoad: true,
                isApple: isApple,
                isOrphaned: isOrphaned,
                sizeBytes: size,
                bundleIdentifier: nil
            ))
        }

        return results
    }

    private static func scanDirectory(_ dir: URL, type: StartupItemType) -> [StartupItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return []
        }

        var results: [StartupItem] = []
        for file in files {
            let filename = file.lastPathComponent
            let isPlist = filename.hasSuffix(".plist")
            let isDisabledPlist = filename.hasSuffix(".plist.disabled")
            guard isPlist || isDisabledPlist else { continue }

            guard let dict = NSDictionary(contentsOf: file) as? [String: Any] else { continue }

            let label = (dict["Label"] as? String) ?? filename.replacingOccurrences(of: ".plist.disabled", with: "").replacingOccurrences(of: ".plist", with: "")
            let isApple = label.lowercased().hasPrefix("com.apple.") || file.path.contains("/System/")
            let disabledDict = (dict["Disabled"] as? Bool) ?? false
            let isEnabled = !isDisabledPlist && !disabledDict
            let runAtLoad = (dict["RunAtLoad"] as? Bool) ?? false

            var exePath = dict["Program"] as? String
            let args = dict["ProgramArguments"] as? [String] ?? []
            if exePath == nil, let firstArg = args.first {
                exePath = firstArg
            }
            if let rawExe = exePath {
                exePath = NSString(string: rawExe).expandingTildeInPath
            }

            var size: Int64 = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            var exeExists = true
            let wrappers: Set<String> = ["/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env", "/usr/bin/open"]
            if let exe = exePath {
                if wrappers.contains(exe), args.count > 1,
                   let targetArg = args.dropFirst().first(where: { $0.hasPrefix("/") || $0.hasPrefix("~") }) {
                    let expandedTarget = NSString(string: targetArg).expandingTildeInPath
                    exeExists = FileManager.default.fileExists(atPath: expandedTarget)
                } else {
                    let exists = FileManager.default.fileExists(atPath: exe)
                    exeExists = exists
                    if exists {
                        let exeURL = URL(fileURLWithPath: exe)
                        let exeSize = (try? exeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                        size += exeSize
                    }
                }
            }
            let isOrphaned = !isApple && exePath != nil && !exeExists

            let friendlyName = generateFriendlyName(label: label, exePath: exePath)

            results.append(StartupItem(
                id: file.path,
                name: friendlyName,
                label: label,
                type: type,
                plistURL: file,
                executablePath: exePath,
                arguments: args,
                isEnabled: isEnabled,
                runAtLoad: runAtLoad,
                isApple: isApple,
                isOrphaned: isOrphaned,
                sizeBytes: size,
                bundleIdentifier: dict["CFBundleIdentifier"] as? String
            ))
        }

        return results
    }

    private static func generateFriendlyName(label: String, exePath: String?) -> String {
        if let exe = exePath {
            let last = (exe as NSString).lastPathComponent
            if !last.isEmpty && last != "sh" && last != "bash" && last != "zsh" && last != "env" && last != "open" {
                return last
            }
        }
        let parts = label.split(separator: ".")
        if let last = parts.last, !last.isEmpty {
            return String(last)
        }
        return label
    }

    static func trashDestination(
        for url: URL,
        trashDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
    ) -> URL {
        let fm = FileManager.default
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = trashDirectory.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            candidate = trashDirectory.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    static func adminMoveToTrashCommand(for plistURL: URL, domain: String, label: String, uid: uid_t) -> String {
        let dest = trashDestination(for: plistURL).path
        let path = plistURL.path
        return "launchctl bootout \(domain)/\(label) 2>/dev/null; mv \"\(path)\" \"\(dest)\" && chown \(uid) \"\(dest)\""
    }

    private static func runAsAdmin(_ command: String) async -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let output = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: .seconds(60))
        return output?.succeeded == true
    }

    func toggleItem(_ item: StartupItem, enable: Bool) async -> Bool {
        if item.type == .loginItem {
            let escapedName = item.name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            if enable {
                guard let exe = item.executablePath, FileManager.default.fileExists(atPath: exe) else { return false }
                let escapedPath = exe
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let script = "tell application \"System Events\" to make login item at end with properties {path:\"\(escapedPath)\", hidden:false}"
                let output = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: .seconds(15))
                return output?.succeeded == true
            } else {
                let script = "tell application \"System Events\" to delete (every login item whose name is \"\(escapedName)\")"
                let output = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: .seconds(15))
                return output?.succeeded == true
            }
        }

        guard let plistURL = item.plistURL, !item.isApple else { return false }

        let fm = FileManager.default
        let path = plistURL.path
        let requiresAdmin = item.requiresAdministrator || !fm.isWritableFile(atPath: path)
        let uid = getuid()

        if enable {

            if path.hasSuffix(".disabled") {
                let newPath = String(path.dropLast(".disabled".count))
                if requiresAdmin {
                    return await Self.runAsAdmin("mv \"\(path)\" \"\(newPath)\"")
                } else {
                    do {
                        try fm.moveItem(atPath: path, toPath: newPath)
                        return true
                    } catch {
                        return false
                    }
                }
            } else {
                if requiresAdmin {
                    return await Self.runAsAdmin("/usr/libexec/PlistBuddy -c 'Set :Disabled false' \"\(path)\" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add :Disabled bool false' \"\(path)\"")
                } else if var dict = NSDictionary(contentsOf: plistURL) as? [String: Any] {
                    dict["Disabled"] = false
                    return (dict as NSDictionary).write(to: plistURL, atomically: true)
                }
            }
        } else {

            let newPath = path + ".disabled"
            if requiresAdmin {
                let domain = item.type == .systemDaemon ? "system" : "gui/\(uid)"
                return await Self.runAsAdmin("launchctl bootout \(domain)/\(item.label) 2>/dev/null; mv \"\(path)\" \"\(newPath)\"")
            } else {
                _ = await ProcessRunner.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(item.label)"], timeout: .seconds(10))

                do {
                    try fm.moveItem(atPath: path, toPath: newPath)
                    return true
                } catch {
                    if var dict = NSDictionary(contentsOf: plistURL) as? [String: Any] {
                        dict["Disabled"] = true
                        return (dict as NSDictionary).write(to: plistURL, atomically: true)
                    }
                    return false
                }
            }
        }
        return false
    }

    func removeItem(_ item: StartupItem) async -> Bool {
        if item.type == .loginItem {
            let escapedName = item.name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"System Events\" to delete (every login item whose name is \"\(escapedName)\")"
            let output = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: .seconds(15))
            let success = output?.succeeded == true
            if success {
                OperationLogger.shared.log(
                    action: localized("Removed startup item"),
                    itemsCleaned: 1,
                    bytesFreed: item.sizeBytes,
                    details: "\(item.name) (Login Item)"
                )
            }
            return success
        }

        guard let plistURL = item.plistURL, !item.isApple else { return false }
        guard !WhitelistManager.shared.blocksRemoval(of: plistURL.path) else { return false }

        let fm = FileManager.default
        let path = plistURL.path
        let requiresAdmin = item.requiresAdministrator || !fm.isWritableFile(atPath: path)
        let uid = getuid()

        if requiresAdmin {
            let domain = item.type == .systemDaemon ? "system" : "gui/\(uid)"
            let command = Self.adminMoveToTrashCommand(for: plistURL, domain: domain, label: item.label, uid: uid)
            let success = await Self.runAsAdmin(command)
            if success {
                OperationLogger.shared.log(
                    action: localized("Removed startup item"),
                    itemsCleaned: 1,
                    bytesFreed: item.sizeBytes,
                    details: "\(item.name) (\(item.label))"
                )
            }
            return success
        } else {
            _ = await ProcessRunner.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(item.label)"], timeout: .seconds(10))

            do {
                try fm.trashItem(at: plistURL, resultingItemURL: nil)
                OperationLogger.shared.log(
                    action: localized("Removed startup item"),
                    itemsCleaned: 1,
                    bytesFreed: item.sizeBytes,
                    details: "\(item.name) (\(item.label))"
                )
                return true
            } catch {
                return false
            }
        }
    }
}
