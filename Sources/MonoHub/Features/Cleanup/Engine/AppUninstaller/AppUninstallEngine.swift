import AppKit
import Foundation

nonisolated enum AppUninstallEngine {
    @MainActor
    static func quitRunningInstances(of app: AppItem, timeout: Duration = .seconds(6)) async -> Bool {
        let targetPath = app.bundleURL.standardizedFileURL.path
        let instances = NSWorkspace.shared.runningApplications.filter { running in
            if running.bundleURL?.standardizedFileURL.path == targetPath { return true }
            return !app.bundleIdentifier.isEmpty && running.bundleIdentifier == app.bundleIdentifier
        }
        guard !instances.isEmpty else { return true }

        for instance in instances {
            _ = instance.terminate()
        }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if instances.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return instances.allSatisfy(\.isTerminated)
    }

    static func removalTargets(for remnants: [RemnantItem]) -> [RemovalTarget] {
        let roots = RemnantFinder.uninstallRoots
        return remnants.map {
            RemovalTarget(url: $0.url, displayName: $0.displayName, size: $0.size, allowedRoots: roots)
        }
    }

    @MainActor
    static func uninstall(app: AppItem, remnants: [RemnantItem], options: CleanupOptions) async -> RemovalReport {
        guard !app.isProtected else {
            return RemovalReport(errors: [localized("%@ is a protected system app and cannot be removed.", app.name)])
        }
        guard await quitRunningInstances(of: app) else {
            return RemovalReport(errors: [localized("%@ is still running. Save your documents, close the app, and try again.", app.name)])
        }
        let name = app.name
        let identifier = app.bundleIdentifier
        return await CleanupExecutor.execute(
            removalTargets(for: remnants),
            options: options,
            action: localized("App Uninstallation: %@", name),
            details: { report in localized("Removed %d items from %@", report.removedURLs.count, identifier) }
        )
    }

    static func removeOrphans(_ orphans: [OrphanItem], options: CleanupOptions) async -> RemovalReport {
        let roots = OrphanScanner.allowedRoots
        let targets = orphans.map {
            RemovalTarget(url: $0.url, displayName: $0.name, size: $0.size, allowedRoots: roots)
        }
        return await CleanupExecutor.execute(
            targets,
            options: options,
            action: localized("Orphaned Remnants Clean"),
            details: { report in localized("Removed %d remnants of uninstalled apps", report.removedURLs.count) }
        )
    }
}
