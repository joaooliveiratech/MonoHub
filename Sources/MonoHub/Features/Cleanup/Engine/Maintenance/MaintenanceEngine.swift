import Foundation

nonisolated struct MaintenanceOutcome: Sendable, Equatable {
    let success: Bool
    let message: String
}

nonisolated enum MaintenanceCommand: Sendable, Equatable {
    case run(executable: String, arguments: [String])
    case administrator(shellCommand: String)
    case removeCache(relativePath: String)
    case rebuildMailEnvelopeIndex
}

nonisolated final class MaintenanceEngine: Sendable {
    static let shared = MaintenanceEngine()

    private init() {}

    static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static var defaultTasks: [MaintenanceTask] {
        [
            MaintenanceTask(
                id: "flush_dns",
                title: localized("Flush DNS Cache"),
                description: localized("Empties the name resolution cache and restarts mDNSResponder."),
                whenToUse: localized("When sites or domains do not load after changing networks, VPN, or DNS."),
                category: localized("Network"),
                systemIcon: "network",
                requiresAdministrator: true
            ),
            MaintenanceTask(
                id: "rebuild_launchservices",
                title: localized("Rebuild LaunchServices"),
                description: localized("Fixes file associations, mismatched icons, and duplicates in “Open With”."),
                whenToUse: localized("When an uninstalled app still appears in “Open With” or icons are blank."),
                category: localized("System"),
                systemIcon: "square.grid.2x2"
            ),
            MaintenanceTask(
                id: "purge_ram",
                title: localized("Purge Inactive Memory"),
                description: localized("Requests the kernel to discard disk cache pages retained in RAM."),
                whenToUse: localized("When memory is under pressure after closing heavy applications."),
                category: localized("Memory"),
                systemIcon: "memorychip",
                requiresAdministrator: true
            ),
            MaintenanceTask(
                id: "restart_coreaudio",
                title: localized("Restart Audio Subsystem (CoreAudio)"),
                description: localized("Restarts the coreaudiod sound daemon without rebooting."),
                whenToUse: localized("When audio is crackling, volume is stuck, or Bluetooth/AirPods output fails."),
                category: localized("Interface"),
                systemIcon: "speaker.wave.3.fill",
                requiresAdministrator: true
            ),
            MaintenanceTask(
                id: "reset_quicklook",
                title: localized("Reset Quick Look Cache"),
                description: localized("Reloads thumbnail and preview generators."),
                whenToUse: localized("When Finder thumbnails appear broken or outdated."),
                category: localized("Interface"),
                systemIcon: "eye"
            ),
            MaintenanceTask(
                id: "restart_finder_dock",
                title: localized("Restart Finder and Dock"),
                description: localized("Restarts the Finder and Dock processes without rebooting the Mac."),
                whenToUse: localized("When Finder freezes or the Dock becomes misaligned."),
                category: localized("Interface"),
                systemIcon: "arrow.clockwise"
            ),
            MaintenanceTask(
                id: "rebuild_spotlight_home",
                title: localized("Rebuild User Spotlight Index"),
                description: localized("Requests mdimport to reindex user documents and files in the Spotlight database."),
                whenToUse: localized("When Spotlight, Raycast, or Finder search cannot find recent files or downloads."),
                category: localized("System"),
                systemIcon: "magnifyingglass",
                requiresAdministrator: false
            ),
            MaintenanceTask(
                id: "thin_timemachine_snapshots",
                title: localized("Purge Time Machine Local Snapshots"),
                description: localized("Reduces local APFS snapshots retained by Time Machine on internal storage."),
                whenToUse: localized("When “System Data” occupies excessive space and freed files do not reclaim disk capacity."),
                category: localized("Storage"),
                systemIcon: "clock.arrow.circlepath",
                requiresAdministrator: true
            ),
            MaintenanceTask(
                id: "run_periodic_scripts",
                title: localized("Run Periodic Maintenance Scripts"),
                description: localized("Executes macOS daily, weekly, and monthly system maintenance routines."),
                whenToUse: localized("For routine operating system hygiene, log rotation, and Unix subsystem maintenance."),
                category: localized("System"),
                systemIcon: "wrench.and.screwdriver",
                requiresAdministrator: true
            ),
            MaintenanceTask(
                id: "clear_font_cache",
                title: localized("Clear Font Cache"),
                description: localized("Removes user font databases so macOS can recreate them."),
                whenToUse: localized("When text appears with garbled characters or fonts fail to render."),
                category: localized("System"),
                systemIcon: "textformat"
            ),
            MaintenanceTask(
                id: "rebuild_mail_index",
                title: localized("Rebuild Mail Envelope Index"),
                description: localized("Removes corrupted message envelope indexes so Apple Mail rebuilds its database."),
                whenToUse: localized("When Apple Mail searches are slow, incomplete, or email messages appear blank."),
                category: localized("System"),
                systemIcon: "envelope.fill",
                requiresAdministrator: false
            ),
            MaintenanceTask(
                id: "clear_help_cache",
                title: localized("Clear Help Cache"),
                description: localized("Removes the Help Viewer index so it can be rebuilt."),
                whenToUse: localized("When the Help menu in an app stays blank or freezes during search."),
                category: localized("System"),
                systemIcon: "questionmark.circle"
            )
        ]
    }

    static func commands(for taskID: String) -> [MaintenanceCommand]? {
        switch taskID {
        case "flush_dns":
            return [.administrator(shellCommand: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder")]
        case "rebuild_launchservices":
            return [.run(executable: lsregisterPath, arguments: ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])]
        case "purge_ram":
            return [.administrator(shellCommand: "/usr/sbin/purge")]
        case "restart_coreaudio":
            return [.administrator(shellCommand: "/usr/bin/killall -9 coreaudiod")]
        case "reset_quicklook":
            return [
                .run(executable: "/usr/bin/qlmanage", arguments: ["-r"]),
                .run(executable: "/usr/bin/qlmanage", arguments: ["-r", "cache"])
            ]
        case "restart_finder_dock":
            return [
                .run(executable: "/usr/bin/killall", arguments: ["Finder"]),
                .run(executable: "/usr/bin/killall", arguments: ["Dock"])
            ]
        case "rebuild_spotlight_home":
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            return [.run(executable: "/usr/bin/mdimport", arguments: ["-r", homePath])]
        case "thin_timemachine_snapshots":
            return [.administrator(shellCommand: "/usr/bin/tmutil thinlocalsnapshots / 10000000000 4")]
        case "run_periodic_scripts":
            return [.administrator(shellCommand: "/usr/sbin/periodic daily weekly monthly")]
        case "clear_font_cache":
            return [.run(executable: "/usr/bin/atsutil", arguments: ["databases", "-removeUser"])]
        case "rebuild_mail_index":
            return [.rebuildMailEnvelopeIndex]
        case "clear_help_cache":
            return [.removeCache(relativePath: "com.apple.helpd")]
        default:
            return nil
        }
    }

    private static func administratorScript(for shellCommand: String) -> String {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    private static func run(_ command: MaintenanceCommand, options: CleanupOptions) async -> MaintenanceOutcome {
        switch command {
        case .run(let executable, let arguments):
            guard let output = await ProcessRunner.run(executable, arguments) else {
                return MaintenanceOutcome(success: false, message: localized("Tool unavailable: %@", (executable as NSString).lastPathComponent))
            }
            if output.timedOut {
                return MaintenanceOutcome(success: false, message: localized("Timed out"))
            }
            return MaintenanceOutcome(
                success: output.succeeded,
                message: output.succeeded ? localized("Done") : localized("Completed with warnings (code %d)", output.status)
            )
        case .administrator(let shellCommand):
            guard let output = await ProcessRunner.run("/usr/bin/osascript", ["-e", administratorScript(for: shellCommand)], timeout: .seconds(180)) else {
                return MaintenanceOutcome(success: false, message: localized("Could not request administrator privileges"))
            }
            if output.output.contains("-128") {
                return MaintenanceOutcome(success: false, message: localized("Cancelled"))
            }
            return MaintenanceOutcome(
                success: output.succeeded,
                message: output.succeeded ? localized("Done") : localized("Failed to execute as administrator")
            )
        case .removeCache(let relativePath):
            let caches = SystemCleanEngine.caches
            guard let url = PathSafety.child(named: relativePath, of: caches) else {
                return MaintenanceOutcome(success: false, message: localized("Invalid path"))
            }
            let target = RemovalTarget(url: url, size: 0, allowedRoots: [caches])
            switch SafeFileRemover.remove(target, mode: options.deletionMode) {
            case .removed: return MaintenanceOutcome(success: true, message: localized("Cache removed"))
            case .missing: return MaintenanceOutcome(success: true, message: localized("Nothing to clean"))
            case .refused(let reason), .failed(let reason): return MaintenanceOutcome(success: false, message: reason)
            }
        case .rebuildMailEnvelopeIndex:
            let library = RemnantFinder.homeLibrary
            let mailDir = library.appendingPathComponent("Mail", isDirectory: true)
            guard FileManager.default.fileExists(atPath: mailDir.path) else {
                return MaintenanceOutcome(success: true, message: localized("Nothing to clean"))
            }
            guard let vDirs = try? FileManager.default.contentsOfDirectory(atPath: mailDir.path) else {
                return MaintenanceOutcome(success: true, message: localized("Nothing to clean"))
            }
            var removedCount = 0
            for vDir in vDirs where vDir.hasPrefix("V") {
                let mailData = mailDir.appendingPathComponent(vDir).appendingPathComponent("MailData")
                if let files = try? FileManager.default.contentsOfDirectory(atPath: mailData.path) {
                    for file in files where file.hasPrefix("Envelope Index") {
                        let fileURL = mailData.appendingPathComponent(file)
                        if (try? FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)) != nil {
                            removedCount += 1
                        }
                    }
                }
            }
            if removedCount > 0 {
                return MaintenanceOutcome(success: true, message: localized("Done (Mail will rebuild index on next launch)"))
            } else {
                return MaintenanceOutcome(success: true, message: localized("Mail index is healthy"))
            }
        }
    }

    @concurrent
    func executeTask(_ task: MaintenanceTask, options: CleanupOptions) async -> MaintenanceOutcome {
        guard let commands = Self.commands(for: task.id) else {
            return MaintenanceOutcome(success: false, message: localized("Unknown task"))
        }
        var outcome = MaintenanceOutcome(success: true, message: localized("Done"))
        for command in commands {
            let step = await Self.run(command, options: options)
            if !step.success {
                outcome = step
                if step.message == localized("Cancelled") { break }
            } else if outcome.success {
                outcome = step
            }
        }
        if options.logsOperations && outcome.message != localized("Cancelled") {
            OperationLogger.shared.log(
                action: localized("Optimization: %@", task.title),
                itemsCleaned: outcome.success ? 1 : 0,
                bytesFreed: 0,
                details: localized("Routine %@: %@", task.id, outcome.message)
            )
        }
        return outcome
    }
}
