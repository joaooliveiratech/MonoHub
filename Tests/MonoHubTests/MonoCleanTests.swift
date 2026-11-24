import AppKit
import Foundation
import Testing
@testable import MonoHub

@Suite("MonoClean Core Tests")
@MainActor
struct MonoCleanCoreTests {

    @Test("AppInfo satisfies SemVer and zero telemetry contract")
    func appInfoVerification() {
        #expect(AppInfo.name == "MonoHub")
        #expect(AppInfo.version == "0.17.6")
        #expect(!AppInfo.privacyStatement.isEmpty)
        #expect(AppInfo.privacyStatement.contains("Zero telemetria"))
    }

    @Test("Formatting bytes converts counts accurately")
    func byteFormatting() {
        let zeroStr = Formatting.bytes(Int64(0)).lowercased()
        #expect(zeroStr.contains("zero") || zeroStr.contains("0"))
        #expect(Formatting.bytes(Int64(1024)).localizedCaseInsensitiveContains("KB") || Formatting.bytes(Int64(1024)).localizedCaseInsensitiveContains("kB"))
        #expect(Formatting.bytes(Int64(1_048_576)).localizedCaseInsensitiveContains("MB"))
        #expect(Formatting.bytes(Int64(1_073_741_824)).localizedCaseInsensitiveContains("GB"))
    }

    @Test("Formatting percentage stays bounded")
    func percentageFormatting() {
        #expect(Formatting.percentage(0.5) == "50.0%")
        #expect(Formatting.percentage(1.0) == "100.0%")
        #expect(Formatting.percentage(0.0) == "0.0%")
    }

    @Test("Whitelist protects macOS system paths unconditionally")
    func whitelistSystemProtection() {
        let whitelist = WhitelistManager.shared
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(whitelist.isWhitelisted(path: "/"))
        #expect(whitelist.isWhitelisted(path: "/Users"))
        #expect(whitelist.isWhitelisted(path: home))
        #expect(whitelist.isWhitelisted(path: "\(home)/.ssh"))
        #expect(whitelist.isWhitelisted(path: "\(home)/.aws"))
        #expect(whitelist.isWhitelisted(path: "/System"))
        #expect(whitelist.isWhitelisted(path: "/System/Library/CoreServices"))
        #expect(whitelist.isWhitelisted(path: "/usr/bin"))
        #expect(whitelist.isWhitelisted(path: "/Applications/MonoHub.app"))
    }

    @Test("Whitelist allows adding and removing custom paths")
    func whitelistCustomPaths() throws {
        let configDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configDirectory) }
        let whitelist = WhitelistManager(configDirectory: configDirectory)
        let testPath = "/Users/test/ProtectedFolder"

        whitelist.add(path: testPath)
        #expect(whitelist.isWhitelisted(path: testPath))
        #expect(whitelist.isWhitelisted(path: "\(testPath)/subfile.txt"))
        #expect(!whitelist.isWhitelisted(path: "\(testPath)Sibling"))

        let fileURL = configDirectory.appendingPathComponent("whitelist")
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        let reloaded = WhitelistManager(configDirectory: configDirectory)
        #expect(reloaded.allEntries() == [testPath])

        whitelist.remove(path: testPath)
        #expect(!whitelist.isWhitelisted(path: testPath))
    }

    @Test("Volume statistics reads root filesystem capacity")
    func volumeStatsVerification() {
        let stats = DiskAnalyzerEngine.shared.getVolumeStats()
        #expect(stats.totalBytes > 0)
        #expect(stats.freeBytes > 0)
        #expect(stats.usedBytes > 0)
        #expect(stats.usedPercentage >= 0.0 && stats.usedPercentage <= 1.0)
    }

    @Test("SystemMonitor samples valid metrics without errors")
    func systemMonitorSampling() {
        let metrics = SystemMonitorEngine.shared.sampleMetrics()
        #expect(metrics.cpuUsage >= 0.0 && metrics.cpuUsage <= 1.0)
        #expect(metrics.memoryTotalBytes > 0)
        #expect(metrics.memoryPressure >= 0.0 && metrics.memoryPressure <= 1.0)
        #expect(metrics.diskFreeBytes > 0)
    }

    @Test("OperationLogger records and retrieves local records")
    func operationLoggerVerification() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = OperationLogger(directory: directory)
        let testAction = "Teste de Limpeza Unittest"
        let testBytes: Int64 = 42_000_000

        logger.log(action: testAction, itemsCleaned: 3, bytesFreed: testBytes, details: "Detalhe\tcom\ntabs")
        let records = logger.fetchRecords()

        #expect(records.count == 1)
        #expect(records.first?.action == testAction)
        #expect(records.first?.bytesFreed == testBytes)
        #expect(records.first?.details == "Detalhe com tabs")

        let permissions = try FileManager.default.attributesOfItem(atPath: logger.logFileURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        logger.clearLogs()
        #expect(logger.fetchRecords().isEmpty)
    }

    @Test("OperationLogger rotates the log once it exceeds the size cap")
    func operationLoggerRotation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = OperationLogger(directory: directory)
        logger.log(action: "Primeiro", itemsCleaned: 1, bytesFreed: 1, details: "x")
        let padding = Data(repeating: 0x41, count: Int(OperationLogger.maximumFileBytes))
        let handle = try FileHandle(forWritingTo: logger.logFileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: padding)
        try handle.close()

        logger.log(action: "Depois da rotação", itemsCleaned: 1, bytesFreed: 1, details: "y")

        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("operations.log.1").path))
        #expect(logger.fetchRecords().map(\.action) == ["Depois da rotação"])
    }

    @Test("LargeFileType detects extensions correctly")
    func largeFileTypeDetection() {
        #expect(LargeFileType.detect(for: URL(fileURLWithPath: "/path/installer.dmg")) == .installer)
        #expect(LargeFileType.detect(for: URL(fileURLWithPath: "/path/video.mp4")) == .video)
        #expect(LargeFileType.detect(for: URL(fileURLWithPath: "/path/archive.tar.gz")) == .archive)
        #expect(LargeFileType.detect(for: URL(fileURLWithPath: "/path/disk.iso")) == .installer)
        #expect(LargeFileType.detect(for: URL(fileURLWithPath: "/path/data.unknown")) == .other)
    }

    @Test("MaintenanceEngine has predefined maintenance routines")
    func maintenanceTasksIntegrity() {
        let tasks = MaintenanceEngine.defaultTasks
        #expect(tasks.count >= 10)
        #expect(tasks.contains { $0.id == "flush_dns" })
        #expect(tasks.contains { $0.id == "rebuild_launchservices" })
        #expect(tasks.contains { $0.id == "purge_ram" })
        #expect(tasks.contains { $0.id == "restart_coreaudio" })
        #expect(tasks.contains { $0.id == "reset_quicklook" })
        #expect(tasks.contains { $0.id == "rebuild_spotlight_home" })
        #expect(tasks.contains { $0.id == "thin_timemachine_snapshots" })
        #expect(tasks.contains { $0.id == "run_periodic_scripts" })
        #expect(tasks.contains { $0.id == "clear_font_cache" })
        #expect(tasks.contains { $0.id == "rebuild_mail_index" })
        #expect(tasks.contains { $0.id == "clear_help_cache" })
    }

    @Test("RemnantFinder calculates directory sizes accurately")
    func remnantFinderSizeCalculation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleFile = tempDir.appendingPathComponent("test.dat")
        let data = Data(repeating: 0xAB, count: 2048)
        try data.write(to: sampleFile)

        let size = RemnantFinder.shared.calculateSize(of: tempDir)
        #expect(size >= 2048)
    }

    @Test("Formatting relativeDate outputs localized string respecting language")
    func relativeDateLocalization() {
        let now = Date()
        let past = now.addingTimeInterval(-3600 * 24 * 3) // 3 days ago
        let original = Localization.language
        defer { Localization.language = original }

        Localization.language = .portuguese
        let formattedPt = Formatting.relativeDate(past)
        #expect(formattedPt.contains("há") || formattedPt.contains("dia"))

        Localization.language = .english
        let formattedEn = Formatting.relativeDate(past)
        #expect(formattedEn.contains("ago") || formattedEn.contains("day"))
    }

    @Test("ProjectArtifact comes unselected by default for safety")
    func projectArtifactSafetyDefault() {
        let recentArtifact = ProjectArtifact(
            projectName: "ActiveApp",
            artifactType: ".build",
            path: URL(fileURLWithPath: "/path/to/build"),
            size: 5000,
            lastModified: Date()
        )
        #expect(recentArtifact.isRecent == true)
        #expect(recentArtifact.isSelected == false)

        let oldDate = Date().addingTimeInterval(-3600 * 24 * 7) // 7 days ago
        let oldArtifact = ProjectArtifact(
            projectName: "InactiveApp",
            artifactType: "node_modules",
            path: URL(fileURLWithPath: "/path/to/node_modules"),
            size: 5000,
            lastModified: oldDate
        )
        #expect(oldArtifact.isRecent == false)
        #expect(oldArtifact.isSelected == false)
    }

    @Test("CleanCategoryGroup evaluates tri-state selection accurately")
    func cleanCategoryGroupSelectionState() {
        let item1 = CleanSubItem(name: "A", url: URL(fileURLWithPath: "/tmp/a"), size: 100, isSelected: true)
        let item2 = CleanSubItem(name: "B", url: URL(fileURLWithPath: "/tmp/b"), size: 200, isSelected: false)

        let group = CleanCategoryGroup(type: .userCaches, items: [item1, item2], isSelected: true)
        #expect(group.isPartiallySelected == true)
        #expect(group.isAllSelected == false)
        #expect(group.hasAnySelected == true)
        #expect(group.selectedCount == 1)
        #expect(group.totalCount == 2)
        #expect(group.selectedSize == 100)

        // Cascade unselection when initialized with isSelected: false
        let unselectedGroup = CleanCategoryGroup(type: .trash, items: [item1, item2], isSelected: false)
        #expect(unselectedGroup.isAllSelected == false)
        #expect(unselectedGroup.isPartiallySelected == false)
        #expect(unselectedGroup.hasAnySelected == false)
        #expect(unselectedGroup.selectedCount == 0)
    }

    @Test("ExecutionResult satisfies unified contract across engines")
    func executionResultContract() {
        let res = ExecutionResult(success: true, itemsCount: 42, bytesFreed: 1024 * 1024, errors: [])
        #expect(res.success == true)
        #expect(res.itemsCount == 42)
        #expect(res.itemsRemoved == 42)
        #expect(res.itemsPurged == 42)
        #expect(res.bytesFreed == 1024 * 1024)
        #expect(res.errors.isEmpty)
    }

    @Test("CleanCategoryGroup and CleanSubItem default to unselected")
    func cleanCategoryDefaultUnselected() {
        let subItem = CleanSubItem(name: "TestCache", url: URL(fileURLWithPath: "/tmp/cache"), size: 1024)
        #expect(subItem.isSelected == false)

        let group = CleanCategoryGroup(type: .userCaches, items: [subItem])
        #expect(group.isSelected == false)
        #expect(group.hasAnySelected == false)
        #expect(group.selectedCount == 0)
    }

    @Test("PermissionsManager provides valid bundle path and clipboard copy")
    func permissionsManagerContract() {
        let manager = PermissionsManager.shared
        #expect(!manager.appPath.isEmpty)
        #expect(manager.appBundleURL.isFileURL)
        #expect(manager.appPath.hasSuffix(".app") || manager.appPath.contains("/"))

        // Test clipboard copy
        manager.copyAppPathToClipboard()
        let copied = NSPasteboard.general.string(forType: .string)
        #expect(copied == manager.appPath)
    }

    @Test("HubNavigation and Menu Bar toggle integrate Clean and Stats modules")
    func unifiedHubNavigationAndMenuBarToggle() {
        let nav = HubNavigation.shared
        nav.select(.menuBar)
        #expect(nav.selectedItem == .menuBar)

        nav.select(.dashboard)
        #expect(nav.selectedItem == .dashboard)

        let prefs = MonitorPreferences.shared
        let original = prefs.isMenuBarEnabled
        defer { prefs.isMenuBarEnabled = original }

        prefs.isMenuBarEnabled = false
        #expect(prefs.orderedEnabledModules.isEmpty)

        prefs.isMenuBarEnabled = true
        #expect(!prefs.orderedEnabledModules.isEmpty)
    }
}

@Suite("MonoClean Deletion Safety")
struct MonoCleanSafetyTests {
    private func makeSandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoCleanTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ url: URL, bytes: Int = 16) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x1, count: bytes).write(to: url)
    }

    private func isolatedWhitelist() -> WhitelistManager {
        WhitelistManager(configDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test("Bundle identifiers and path components reject traversal")
    func pathSafetyValidation() {
        #expect(PathSafety.isValidBundleIdentifier("com.example.App-2_beta"))
        #expect(!PathSafety.isValidBundleIdentifier("../../Documents"))
        #expect(!PathSafety.isValidBundleIdentifier("com..example"))
        #expect(!PathSafety.isValidBundleIdentifier("com/example/app"))
        #expect(!PathSafety.isValidBundleIdentifier("noDots"))
        #expect(PathSafety.child(named: "..", of: URL(fileURLWithPath: "/tmp")) == nil)
        #expect(PathSafety.child(named: "a/b", of: URL(fileURLWithPath: "/tmp")) == nil)
        #expect(PathSafety.child(named: ".hidden", of: URL(fileURLWithPath: "/tmp")) == nil)
        #expect(PathSafety.child(named: "Cache", of: URL(fileURLWithPath: "/tmp"))?.path == "/tmp/Cache")
    }

    @Test("Bundle identifier matching respects component boundaries")
    func bundleIdentifierBoundaries() {
        #expect(PathSafety.matchesBundleIdentifier("com.foo.app.plist", bundleIdentifier: "com.foo.app"))
        #expect(PathSafety.matchesBundleIdentifier("com.foo.app.helper.plist", bundleIdentifier: "com.foo.app"))
        #expect(!PathSafety.matchesBundleIdentifier("com.foo.application.plist", bundleIdentifier: "com.foo.app"))
        #expect(PathSafety.groupContainerMatches("ABCDE12345.com.foo.app", bundleIdentifier: "com.foo.app"))
        #expect(PathSafety.groupContainerMatches("group.com.foo.app", bundleIdentifier: "com.foo.app"))
        #expect(!PathSafety.groupContainerMatches("ABCDE12345.com.foo.appstore", bundleIdentifier: "com.foo.app"))
        #expect(PathSafety.nameMatches("Foo-2026-01-01-120000.ips", prefix: "Foo", separators: ["-", "_", "."]))
        #expect(!PathSafety.nameMatches("Football-2026.ips", prefix: "Foo", separators: ["-", "_", "."]))
    }

    @Test("Nested removal targets collapse into their ancestor")
    func nestedTargetsCollapse() {
        let urls = [
            URL(fileURLWithPath: "/x/a/b"),
            URL(fileURLWithPath: "/x/a"),
            URL(fileURLWithPath: "/x/ab"),
            URL(fileURLWithPath: "/x/a/./c")
        ]
        let kept = PathSafety.removingNestedDuplicates(urls).map(\.path).sorted()
        #expect(kept == ["/x/a", "/x/ab"])
    }

    @Test("Remnant finder is bundle-id based and ignores unsafe identifiers")
    func remnantCandidates() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let library = sandbox.appendingPathComponent("Library", isDirectory: true)
        let systemLibrary = sandbox.appendingPathComponent("SystemLibrary", isDirectory: true)
        let bundle = sandbox.appendingPathComponent("Applications/Foo Editor.app", isDirectory: true)
        try touch(bundle.appendingPathComponent("Contents/Info.plist"))
        try touch(library.appendingPathComponent("Application Support/com.foo.editor/data.db"))
        try touch(library.appendingPathComponent("Application Support/Foo Editor/state.json"))
        try touch(library.appendingPathComponent("Preferences/com.foo.editor.plist"))
        try touch(library.appendingPathComponent("Preferences/com.foo.editorial.plist"))
        try touch(library.appendingPathComponent("Containers/com.foo.editor/Data/file"))
        try touch(library.appendingPathComponent("Containers/Foo Editor/Data/file"))
        try touch(library.appendingPathComponent("Group Containers/TEAM.com.foo.editor/file"))
        try touch(library.appendingPathComponent("Group Containers/TEAM.com.foo.editorial/file"))
        try touch(systemLibrary.appendingPathComponent("LaunchAgents/com.foo.editor.helper.plist"))

        let candidates = RemnantFinder.candidates(
            for: bundle,
            bundleIdentifier: "com.foo.editor",
            appName: "Foo Editor",
            library: library,
            systemLibrary: systemLibrary,
            whitelist: isolatedWhitelist()
        )
        let names = Set(candidates.map(\.url.lastPathComponent))
        #expect(names.contains("com.foo.editor.plist"))
        #expect(!names.contains("com.foo.editorial.plist"))
        #expect(names.contains("TEAM.com.foo.editor"))
        #expect(!names.contains("TEAM.com.foo.editorial"))
        #expect(names.contains("com.foo.editor.helper.plist"))
        #expect(candidates.filter { $0.url.lastPathComponent == "Foo Editor" }.allSatisfy { $0.match == .appName })
        #expect(!candidates.contains { $0.category == .containers && $0.url.lastPathComponent == "Foo Editor" })

        let hostile = RemnantFinder.candidates(
            for: bundle,
            bundleIdentifier: "../../..",
            appName: "../..",
            library: library,
            systemLibrary: systemLibrary,
            whitelist: isolatedWhitelist()
        )
        #expect(hostile.count == 1)
        #expect(hostile.first?.category == .appBundle)
    }

    @Test("Safe remover refuses paths outside roots, through symlinks or whitelisted")
    func safeRemoverValidation() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("Caches", isDirectory: true)
        let outside = sandbox.appendingPathComponent("Documents", isDirectory: true)
        try touch(root.appendingPathComponent("app/cache.bin"))
        try touch(outside.appendingPathComponent("precious.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)

        let whitelist = isolatedWhitelist()
        #expect(SafeFileRemover.validate(root.appendingPathComponent("app"), allowedRoots: [root], whitelist: whitelist) == nil)
        #expect(SafeFileRemover.validate(root, allowedRoots: [root], whitelist: whitelist) != nil)
        #expect(SafeFileRemover.validate(outside.appendingPathComponent("precious.txt"), allowedRoots: [root], whitelist: whitelist) != nil)
        #expect(SafeFileRemover.validate(root.appendingPathComponent("escape/precious.txt"), allowedRoots: [root], whitelist: whitelist) != nil)
        #expect(SafeFileRemover.validate(root.appendingPathComponent("app/../../Documents"), allowedRoots: [root], whitelist: whitelist) != nil)
        #expect(SafeFileRemover.validate(URL(fileURLWithPath: "/System/Library"), allowedRoots: [URL(fileURLWithPath: "/System")], whitelist: whitelist) != nil)

        whitelist.add(path: root.appendingPathComponent("app").path)
        #expect(SafeFileRemover.validate(root.appendingPathComponent("app/cache.bin"), allowedRoots: [root], whitelist: whitelist) != nil)
    }

    @Test("Safe remover deletes only validated targets and reports freed bytes")
    func safeRemoverRemoval() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("Caches", isDirectory: true)
        let outside = sandbox.appendingPathComponent("Keep", isDirectory: true)
        let parent = root.appendingPathComponent("vendor", isDirectory: true)
        try touch(parent.appendingPathComponent("nested/blob"))
        try touch(outside.appendingPathComponent("keep.txt"))

        let report = SafeFileRemover.removeAll([
            RemovalTarget(url: parent.appendingPathComponent("nested"), size: 10, allowedRoots: [root]),
            RemovalTarget(url: parent, size: 100, allowedRoots: [root]),
            RemovalTarget(url: outside, size: 5, allowedRoots: [root]),
            RemovalTarget(url: root.appendingPathComponent("missing"), size: 7, allowedRoots: [root])
        ], mode: .deletePermanently, whitelist: isolatedWhitelist())

        #expect(report.removedURLs.count == 1)
        #expect(report.bytesFreed == 100)
        #expect(report.errors.count == 1)
        #expect(!FileManager.default.fileExists(atPath: parent.path))
        #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("keep.txt").path))
    }

    @Test("Project purge finds artifacts only next to project markers and never follows symlinks")
    func projectPurgeDiscovery() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try touch(sandbox.appendingPathComponent("web/package.json"))
        try touch(sandbox.appendingPathComponent("web/node_modules/left-pad/index.js"))
        try touch(sandbox.appendingPathComponent("web/node_modules/dep/node_modules/x/index.js"))
        try touch(sandbox.appendingPathComponent("notes/build/important.md"))
        try touch(sandbox.appendingPathComponent("notes/build/rust/Cargo.toml"))
        try touch(sandbox.appendingPathComponent("notes/build/rust/target/debug/bin"))
        try touch(sandbox.appendingPathComponent("py/.venv/pyvenv.cfg"))
        try touch(sandbox.appendingPathComponent("fake/.venv/readme.txt"))
        try touch(sandbox.appendingPathComponent("nextjs/package.json"))
        try touch(sandbox.appendingPathComponent("nextjs/.next/BUILD_ID"))
        try touch(sandbox.appendingPathComponent("turborepo/turbo.json"))
        try touch(sandbox.appendingPathComponent("turborepo/.turbo/cache"))
        try touch(sandbox.appendingPathComponent("pytestproj/pyproject.toml"))
        try touch(sandbox.appendingPathComponent("pytestproj/.pytest_cache/v"))
        try FileManager.default.createSymbolicLink(
            at: sandbox.appendingPathComponent("link"),
            withDestinationURL: sandbox.appendingPathComponent("web")
        )

        let found = ProjectPurgeEngine.discoverArtifacts(in: sandbox, maxDepth: 6, olderThan: nil)
        let relative = Set(found.map { String($0.url.path.dropFirst(sandbox.path.count + 1)) })
        #expect(relative == ["web/node_modules", "notes/build/rust/target", "py/.venv", "nextjs/.next", "turborepo/.turbo", "pytestproj/.pytest_cache"])

        let shallow = ProjectPurgeEngine.discoverArtifacts(in: sandbox, maxDepth: 1, olderThan: nil)
        #expect(!shallow.contains { $0.url.path.hasSuffix("rust/target") })

        let future = ProjectPurgeEngine.discoverArtifacts(in: sandbox, maxDepth: 6, olderThan: Date().addingTimeInterval(-86_400))
        #expect(future.isEmpty)
    }

    @Test("Orphan detection is conservative and bundle-id based")
    func orphanHeuristics() {
        let installed = InstalledAppIndex(identifiers: ["com.vendor.editor", "io.tool.app"])
        let never: (String) -> Bool = { _ in false }
        #expect(OrphanScanner.isLikelyOrphan(identifier: "com.gone.player", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "com.vendor.editor", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "com.vendor.editor.ShareExtension", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "com.vendor.othertool", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "com.apple.Safari", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "group.com.gone.player", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "com.google.Chrome", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "Random Folder", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "com.gone", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "com.gone.player.helper", installed: installed) { $0 == "com.gone.player" })
    }

    @Test("Orphan detection recognizes uninstalled app names while protecting active and system names")
    func orphanAppNameHeuristics() {
        let installed = InstalledAppIndex(
            identifiers: ["com.spotify.client", "com.tinyspeck.slackmacgap"],
            names: ["Spotify", "Slack"],
            runningIdentifiers: ["com.tinyspeck.slackmacgap"],
            runningNames: ["Slack"]
        )

        // Uninstalled apps:
        #expect(OrphanScanner.isLikelyOrphanAppName(name: "Discord", installed: installed))
        #expect(OrphanScanner.isLikelyOrphanAppName(name: "Telegram Desktop", installed: installed))
        #expect(OrphanScanner.isLikelyOrphanAppName(name: "Postman", installed: installed))
        #expect(OrphanScanner.isLikelyOrphanAppName(name: "Sublime Text", installed: installed))

        // Active/installed apps:
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Spotify", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Slack", installed: installed))

        // System, generic, vendor directories:
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Google", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Microsoft", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Adobe", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Apple", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Caches", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Logs", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Application Support", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "CrashReporter", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Saved Application State", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Preferences", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Homebrew", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "pnpm", installed: installed))

        // Path safety & length constraints:
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "..", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "ab", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "a/b", installed: installed))
    }

    @Test("SystemCleanEngine includes mail downloads and developer caches")
    func systemCleanLocations() {
        let roots = SystemCleanEngine.allowedRoots(for: .mailDownloads)
        #expect(!roots.isEmpty)
        #expect(CleanCategoryType.mailDownloads.safetyLevel == .caution)
        #expect(CleanCategoryType.userCaches.safetyLevel == .safe)
    }

    @Test("Time Machine local snapshot parsing and dates")
    func timeMachineSnapshotParsing() {
        let sampleOutput = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-10-29-081050.local
        com.apple.TimeMachine.2026-10-29-123456.local
        NOTE: local snapshots are considered purgeable and may be removed at any time by deleted(8).
        """
        let names = SystemCleanEngine.parseSnapshotList(sampleOutput)
        #expect(names == [
            "com.apple.TimeMachine.2026-10-29-081050.local",
            "com.apple.TimeMachine.2026-10-29-123456.local"
        ])

        let date1 = SystemCleanEngine.snapshotDate(from: "com.apple.TimeMachine.2026-10-29-081050.local")
        #expect(date1 == "2026-10-29-081050")

        let date2 = SystemCleanEngine.snapshotDate(from: "2026-10-29-123456")
        #expect(date2 == "2026-10-29-123456")

        let formatted = SystemCleanEngine.formatSnapshotDate("2026-10-29-081050")
        #expect(formatted != nil && !formatted!.isEmpty)

        #expect(CleanCategoryType.timeMachineSnapshots.safetyLevel == .safe)
        #expect(CleanCategoryType.timeMachineSnapshots.systemIcon == "clock.arrow.circlepath")
        #expect(!SystemCleanEngine.allowedRoots(for: .timeMachineSnapshots).isEmpty)

        let snapshotItem = CleanSubItem(
            name: "com.apple.TimeMachine.2026-10-29-081050.local",
            customIcon: "clock.arrow.circlepath",
            url: URL(fileURLWithPath: "/Volumes/.timemachine/com.apple.TimeMachine.2026-10-29-081050.local"),
            size: 5_000_000_000
        )
        #expect(snapshotItem.customIcon == "clock.arrow.circlepath")
        #expect(snapshotItem.size == 5_000_000_000)
    }

    @Test("Temporary entries cluster and keep every member path")
    func temporaryClustering() {
        let members = [
            CleanMember(url: URL(fileURLWithPath: "/t/TemporaryDirectory.a"), size: 50_000),
            CleanMember(url: URL(fileURLWithPath: "/t/TemporaryDirectory.b"), size: 30_000),
            CleanMember(url: URL(fileURLWithPath: "/t/big.bin"), size: 900_000),
            CleanMember(url: URL(fileURLWithPath: "/t/tiny"), size: 10),
            CleanMember(url: URL(fileURLWithPath: "/t/empty"), size: 0)
        ]
        let items = SystemCleanEngine.clusterTemporaryEntries(members)
        let allMembers = items.flatMap(\.members).map(\.url.lastPathComponent).sorted()
        #expect(allMembers == ["TemporaryDirectory.a", "TemporaryDirectory.b", "big.bin", "tiny"])
        #expect(items.first { $0.isCluster && $0.members.count == 2 }?.size == 80_000)

        let targets = SystemCleanEngine.removalTargets(for: .tempFiles, items: items)
        #expect(targets.count == 4)
        #expect(targets.reduce(0) { $0 + $1.size } == 980_010)
    }

    @Test("Finder trash listing parser keeps absolute paths only")
    func finderTrashParsing() {
        let parsed = SystemCleanEngine.parseFinderTrashListing("1024\t/Users/x/.Trash/a.txt\nbad line\n2048\t/Users/x/.Trash/Folder/\n12\trelative/path")
        #expect(parsed.map(\.url.path) == ["/Users/x/.Trash/a.txt", "/Users/x/.Trash/Folder"])
        #expect(parsed.map(\.size) == [1024, 2048])
    }

    @Test("User temporary directory is removable while other system paths stay protected")
    func temporaryExemption() {
        let whitelist = isolatedWhitelist()
        let tempItem = FileManager.default.temporaryDirectory.appendingPathComponent("monoclean-probe").path
        #expect(whitelist.isSystemProtected(path: tempItem))
        #expect(!whitelist.isSystemProtected(path: tempItem, exemptingDescendantsOf: SafeFileRemover.userTemporaryRoots))
        #expect(whitelist.isSystemProtected(path: "/private/var/db/foo", exemptingDescendantsOf: SafeFileRemover.userTemporaryRoots))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(whitelist.isSystemProtected(path: "\(home)/Library/Caches"))
        #expect(whitelist.isSystemProtected(path: "\(home)/Library/Logs/MonoHub/operations.log"))
    }

    @Test("Maintenance routines use absolute executables and no user-controlled shell")
    func maintenanceCommands() {
        for task in MaintenanceEngine.defaultTasks {
            let commands = MaintenanceEngine.commands(for: task.id)
            #expect(commands != nil && commands?.isEmpty == false)
            for command in commands ?? [] {
                switch command {
                case .run(let executable, _):
                    #expect(executable.hasPrefix("/"))
                case .administrator(let shellCommand):
                    #expect(task.requiresAdministrator)
                    #expect(shellCommand.hasPrefix("/"))
                case .removeCache(let relativePath):
                    #expect(PathSafety.isSafePathComponent(relativePath))
                case .rebuildMailEnvelopeIndex:
                    #expect(task.id == "rebuild_mail_index")
                }
            }
        }
        #expect(MaintenanceEngine.commands(for: "rm -rf /") == nil)
    }

    @Test("Execution summary caps the number of listed errors")
    func executionSummary() {
        let original = Localization.language
        defer { Localization.language = original }
        Localization.language = .portuguese

        let errors = (1...20).map { "erro \($0)" }
        let result = ExecutionResult(success: false, itemsCount: 2, bytesFreed: 2048, errors: errors)
        #expect(result.summaryTitle == "Concluído com avisos")
        #expect(result.summaryMessage.contains("erro 8"))
        #expect(!result.summaryMessage.contains("erro 9\n"))
        #expect(result.summaryMessage.contains("e mais 12 avisos"))

        Localization.language = .english
        #expect(result.summaryTitle == "Completed with warnings")
        #expect(result.summaryMessage.contains("and 12 more warnings"))
    }
}

@Suite("MonoClean Review Hardening")
struct MonoCleanHardeningTests {
    private func makeSandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonoCleanHardening-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x1, count: 16).write(to: url)
    }

    @Test("dist and build need a git ignore rule unless Gradle owns build")
    func ambiguousArtifactsRequireIgnore() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try touch(sandbox.appendingPathComponent("committed/package.json"))
        try touch(sandbox.appendingPathComponent("committed/dist/index.js"))
        try touch(sandbox.appendingPathComponent("committed/build/icon.icns"))
        try touch(sandbox.appendingPathComponent("ignored/package.json"))
        try touch(sandbox.appendingPathComponent("ignored/.git/HEAD"))
        try touch(sandbox.appendingPathComponent("ignored/.gitignore"))
        try "node_modules\n/dist/\nbuild\n".write(to: sandbox.appendingPathComponent("ignored/.gitignore"), atomically: true, encoding: .utf8)
        try touch(sandbox.appendingPathComponent("ignored/dist/index.js"))
        try touch(sandbox.appendingPathComponent("ignored/build/out.js"))
        try touch(sandbox.appendingPathComponent("android/build.gradle"))
        try touch(sandbox.appendingPathComponent("android/build/outputs/app.apk"))

        let found = ProjectPurgeEngine.discoverArtifacts(in: sandbox, maxDepth: 4, olderThan: nil)
        let relative = Set(found.map { String($0.url.path.dropFirst(sandbox.path.count + 1)) })
        #expect(relative == ["ignored/dist", "ignored/build", "android/build"])
    }

    @Test("Git ignore matching honours anchors and negations")
    func gitIgnoreRules() {
        #expect(ProjectPurgeEngine.ignoreRules(in: "dist\n", matches: "dist"))
        #expect(ProjectPurgeEngine.ignoreRules(in: "/dist/\n", matches: "dist"))
        #expect(ProjectPurgeEngine.ignoreRules(in: "**/build\n", matches: "app/build"))
        #expect(ProjectPurgeEngine.ignoreRules(in: "/build\n", matches: "app/build") == false)
        #expect(ProjectPurgeEngine.ignoreRules(in: "dist\n!dist\n", matches: "dist") == false)
        #expect(ProjectPurgeEngine.ignoreRules(in: "# dist\n", matches: "dist") == false)
    }

    @Test("Temporary directories with recent nested activity are never listed")
    func temporaryRecentActivity() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let old = Date().addingTimeInterval(-3 * 86_400)
        try touch(sandbox.appendingPathComponent("stale/a.bin"))
        try touch(sandbox.appendingPathComponent("active/deep/b.bin"))
        for path in ["stale/a.bin", "stale", "active/deep", "active"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: sandbox.appendingPathComponent(path).path)
        }
        let names = SystemCleanEngine.temporaryCandidates(in: [sandbox]).map(\.lastPathComponent)
        #expect(names.contains("stale"))
        #expect(names.contains("active") == false)
    }

    @Test("Cluster shrinks and renames after a partial removal")
    func clusterPartialRemoval() {
        let members = (1...3).map { CleanMember(url: URL(fileURLWithPath: "/t/x\($0)"), size: 100) }
        let item = CleanSubItem(name: "Sessões (3)", url: members[0].url, members: members, size: 300)
        let partial = item.removing([members[0].url])
        #expect(partial?.members.count == 2)
        #expect(partial?.size == 200)
        #expect(partial?.name == "Sessões (2)")
        #expect(item.removing(Set(members.map(\.url))) == nil)
        #expect(item.removing([]) == item)
    }

    @Test("Password manager caches stay out of the cleanable list")
    func protectedCachePrefixes() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        for name in ["com.1password.1password", "com.example.safe", "com.apple.keychainsharingd"] {
            try touch(sandbox.appendingPathComponent("\(name)/blob"))
        }
        let names = SystemCleanEngine.cleanableChildren(of: sandbox, skipping: []).map(\.lastPathComponent)
        #expect(names == ["com.example.safe"])
    }

    @Test("OrphanScanner protects system daemons, test suites, short app names, and existing LaunchAgent binaries")
    func orphanSystemDaemonAndLaunchAgentProtection() throws {
        let installed = InstalledAppIndex(
            identifiers: ["com.obsproject.obs-studio", "net.ankimobile.anki", "dev.zed.Zed"],
            names: ["OBS", "Anki", "Zed"]
        )
        let never: (String) -> Bool = { _ in false }

        // Test suite domains and non-TLD identifiers must never be flagged as orphans
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "MonoHubTests.notch.abc", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "test.teleprompter.clamping.123", installed: installed, isRegistered: never))
        #expect(!OrphanScanner.isLikelyOrphan(identifier: "com.antigravity.monohub.tests.features", installed: installed, isRegistered: never))

        // Derived bundle ID components and numbered/hyphenated variants of installed apps stay protected
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "obs-studio", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Anki2", installed: installed))
        #expect(!OrphanScanner.isLikelyOrphanAppName(name: "Zed", installed: installed))

        // Apple system daemons & frameworks without com.apple prefix stay protected
        for sysName in ["GeoServices", "PassKit", "GameKit", "SiriEntityCache", "CloudDocs", "DifferentialPrivacy", "TokenBucketRateLimiter", "ContextStoreAgent", "pbs", "sharedfilelistd", "familycircled"] {
            #expect(!OrphanScanner.isLikelyOrphanAppName(name: sysName, installed: installed))
        }

        // LaunchAgent pointing to an existing binary (/bin/sh) must NOT be marked broken even if Label is an unknown bundle ID
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let validAgentURL = sandbox.appendingPathComponent("com.custom.cli.agent.plist")
        let validPlist: [String: Any] = [
            "Label": "com.custom.cli.agent",
            "Program": "/bin/ls"
        ]
        let validData = try PropertyListSerialization.data(fromPropertyList: validPlist, format: .xml, options: 0)
        try validData.write(to: validAgentURL)
        let validCheck = OrphanScanner.inspectLaunchAgent(at: validAgentURL, installed: installed, isRegistered: never)
        #expect(validCheck.isBroken == false)

        // LaunchAgent pointing to a missing binary MUST be marked broken
        let brokenAgentURL = sandbox.appendingPathComponent("com.removed.app.agent.plist")
        let brokenPlist: [String: Any] = [
            "Label": "com.removed.app.agent",
            "Program": "/Applications/RemovedApp.app/Contents/MacOS/RemovedApp"
        ]
        let brokenData = try PropertyListSerialization.data(fromPropertyList: brokenPlist, format: .xml, options: 0)
        try brokenData.write(to: brokenAgentURL)
        let brokenCheck = OrphanScanner.inspectLaunchAgent(at: brokenAgentURL, installed: installed, isRegistered: never)
        #expect(brokenCheck.isBroken == true)
    }

    @Test("DuplicatesEngine guarantees at least one original copy is kept in every group")
    func duplicatesAlwaysKeepOneCopy() {
        let item1 = DuplicateItem(
            url: URL(fileURLWithPath: "/tmp/a1.txt"),
            name: "a1.txt",
            path: "/tmp",
            size: 1024,
            modifiedDate: Date().addingTimeInterval(-100),
            hash: "h1",
            isSelected: true
        )
        let item2 = DuplicateItem(
            url: URL(fileURLWithPath: "/tmp/a2.txt"),
            name: "a2.txt",
            path: "/tmp",
            size: 1024,
            modifiedDate: Date(),
            hash: "h1",
            isSelected: true
        )
        let group = DuplicateGroup(
            id: "h1",
            hash: "h1",
            items: [item1, item2],
            sizePerItem: 1024,
            isVisualSimilarity: false
        )

        let safeToRemove = DuplicatesEngine.safeItemsToRemove(from: [group])
        #expect(safeToRemove.count == 1)
        #expect(safeToRemove.first?.name == "a2.txt")
    }

    @Test("StartupEngine moves privileged plists to Trash instead of rm")
    func startupAdminTrashCommand() {
        let plistURL = URL(fileURLWithPath: "/Library/LaunchDaemons/com.example.daemon.plist")
        let cmd = StartupEngine.adminMoveToTrashCommand(for: plistURL, domain: "system", label: "com.example.daemon", uid: 501)
        #expect(cmd.contains("mv \"/Library/LaunchDaemons/com.example.daemon.plist\""))
        #expect(cmd.contains(".Trash/com.example.daemon.plist"))
        #expect(!cmd.contains("rm "))
    }
}
