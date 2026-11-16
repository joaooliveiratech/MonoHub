import AppKit
import Darwin
import Foundation

nonisolated struct OrphanItem: CleanupListItem, Equatable {
    let id: UUID
    let name: String
    let category: RemnantCategory
    let url: URL
    let size: Int64
    let explanation: String
    var matchType: RemnantMatch
    var safetyLevel: CleanSafetyLevel
    var parentAppHint: String?
    var isSelected: Bool

    var formattedSize: String {
        Formatting.bytes(size)
    }

    var categoryName: String { category.title }
    var itemURL: URL { url }
    var itemName: String { name }
    var itemSize: Int64 { size }

    init(
        id: UUID = UUID(),
        name: String,
        category: RemnantCategory,
        url: URL,
        size: Int64,
        explanation: String = localized("Remnants of uninstalled app"),
        matchType: RemnantMatch = .bundleIdentifier,
        safetyLevel: CleanSafetyLevel = .safe,
        parentAppHint: String? = nil,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.url = url
        self.size = size
        self.explanation = explanation
        self.matchType = matchType
        self.safetyLevel = safetyLevel
        self.parentAppHint = parentAppHint
        self.isSelected = isSelected
    }
}

nonisolated struct InstalledAppIndex: Sendable {
    let identifiers: Set<String>
    let vendors: Set<String>
    let names: Set<String>
    let normalizedNames: Set<String>
    let runningIdentifiers: Set<String>
    let runningNames: Set<String>

    init(
        identifiers: some Sequence<String>,
        names: some Sequence<String> = [] as [String],
        runningIdentifiers: some Sequence<String> = [] as [String],
        runningNames: some Sequence<String> = [] as [String]
    ) {
        let loweredIds = Set(identifiers.map { $0.lowercased() }.filter { !$0.isEmpty })
        self.identifiers = loweredIds
        self.vendors = Set(loweredIds.compactMap(Self.vendor(of:)))

        var derivedNames = Set(names.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        for id in loweredIds {
            let parts = id.split(separator: ".")
            if parts.count >= 3, let last = parts.last, last.count >= 3 {
                derivedNames.insert(String(last))
            }
        }
        self.names = derivedNames
        self.normalizedNames = Set(derivedNames.map(Self.normalize).filter { !$0.isEmpty })

        self.runningIdentifiers = Set(runningIdentifiers.map { $0.lowercased() }.filter { !$0.isEmpty })
        self.runningNames = Set(runningNames.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func normalize(_ string: String) -> String {
        string.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func vendor(of identifier: String) -> String? {
        let components = identifier.split(separator: ".")
        guard components.count >= 3 else { return nil }
        return components.prefix(2).joined(separator: ".")
    }

    func isRelated(to lowerName: String) -> Bool {
        if identifiers.contains(lowerName) || runningIdentifiers.contains(lowerName) { return true }
        if let vendor = Self.vendor(of: lowerName), vendors.contains(vendor) { return true }
        return identifiers.contains { lowerName.hasPrefix($0 + ".") || $0.hasPrefix(lowerName + ".") }
    }

    private static let boundarySeparators: Set<Character> = [" ", "-", "_", "."]

    private static func hasBoundaryPrefix(_ full: String, prefix: String) -> Bool {
        guard prefix.count >= 3, full.hasPrefix(prefix) else { return false }
        guard full.count > prefix.count else { return true }
        let next = full[full.index(full.startIndex, offsetBy: prefix.count)]
        return boundarySeparators.contains(next) || next.isNumber
    }

    func isNameRelated(to rawName: String) -> Bool {
        let lower = rawName.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lower.isEmpty else { return true }
        if names.contains(lower) || runningNames.contains(lower) { return true }
        let normalized = Self.normalize(lower)
        if !normalized.isEmpty && normalizedNames.contains(normalized) { return true }
        let strippedDigits = normalized.trimmingCharacters(in: .decimalDigits)
        if strippedDigits.count >= 3 && normalizedNames.contains(strippedDigits) { return true }
        return names.contains { name in
            name == lower
                || Self.hasBoundaryPrefix(lower, prefix: name)
                || Self.hasBoundaryPrefix(name, prefix: lower)
                || (name.count >= 4 && lower.hasPrefix(name))
                || (lower.count >= 4 && name.hasPrefix(lower))
        }
    }

    static func activeSystemAndToolEnvironment() -> (identifiers: Set<String>, names: Set<String>) {
        var ids = Set<String>()
        var names = Set<String>()
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let maxPids = 4096
        var pids = [pid_t](repeating: 0, count: maxPids)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(maxPids * MemoryLayout<pid_t>.stride))
        if bytes > 0 {
            let count = Int(bytes) / MemoryLayout<pid_t>.stride
            var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            var pathBuf = [CChar](repeating: 0, count: Int( MAXPATHLEN ))
            for i in 0..<count where pids[i] > 0 {
                if proc_name(pids[i], &nameBuf, UInt32(nameBuf.count)) > 0 {
                    let pName = nameBuf.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }.lowercased()
                    if pName.count >= 2 { names.insert(pName) }
                }
                if proc_pidpath(pids[i], &pathBuf, UInt32(pathBuf.count)) > 0 {
                    let path = pathBuf.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                    let last = (path as NSString).lastPathComponent.lowercased()
                    if last.count >= 2 { names.insert(last) }
                }
            }
        }

        let frameworkDirs = [
            "/System/Library/Frameworks",
            "/System/Library/PrivateFrameworks",
            "/System/Library/CoreServices",
            "/Library/Frameworks"
        ]
        for dir in frameworkDirs {
            if let entries = try? fm.contentsOfDirectory(atPath: dir) {
                for entry in entries {
                    let base = (entry as NSString).deletingPathExtension.lowercased()
                    if base.count >= 2 { names.insert(base) }
                }
            }
        }

        let launchDirs = [
            "/System/Library/LaunchAgents",
            "/System/Library/LaunchDaemons",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "\(home)/Library/LaunchAgents"
        ]
        for dir in launchDirs {
            if let entries = try? fm.contentsOfDirectory(atPath: dir) {
                for entry in entries where entry.hasSuffix(".plist") {
                    let base = (entry as NSString).deletingPathExtension.lowercased()
                    if base.contains(".") {
                        ids.insert(base)
                        if let last = base.split(separator: ".").last, last.count >= 3 {
                            names.insert(String(last))
                        }
                    } else if base.count >= 2 {
                        names.insert(base)
                    }
                }
            }
        }

        let binDirs = [
            "/usr/libexec",
            "/usr/sbin",
            "/usr/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/opt/homebrew/Cellar",
            "/opt/homebrew/Caskroom",
            "/usr/local/bin",
            "/usr/local/Cellar",
            "/usr/local/Caskroom",
            "\(home)/.local/bin",
            "\(home)/go/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin"
        ]
        for dir in binDirs {
            if let entries = try? fm.contentsOfDirectory(atPath: dir) {
                for entry in entries where !entry.hasPrefix(".") {
                    let lower = entry.lowercased()
                    if lower.count >= 2 { names.insert(lower) }
                }
            }
        }

        return (ids, names)
    }
}

nonisolated enum OrphanScanMode: Sendable {
    case bundleIdOnly
    case both
    case launchAgents
}

nonisolated enum OrphanScanner {
    private static let protectedPrefixes = [
        "com.apple.", "apple.", "icloud.", "group.", "systemgroup.", "com.icloud.", "org.apple.",
        "com.antigravity.", "org.swift.", "org.chromium."
    ]

    private static let protectedVendorComponents: Set<String> = [
        "apple", "icloud", "microsoft", "google", "docker", "jetbrains", "adobe", "mozilla", "oracle", "antigravity"
    ]

    private static let validReverseDNSTLDs: Set<String> = [
        "com", "org", "net", "io", "app", "dev", "me", "co", "ai", "sh", "gg", "tv", "cc", "xyz",
        "tech", "tools", "work", "pro", "so", "fm", "to", "ly", "vc", "is", "it", "de", "fr", "uk",
        "nl", "ch", "se", "no", "fi", "dk", "es", "pt", "br", "ru", "cn", "jp", "kr", "tw", "hk",
        "sg", "au", "nz", "ca", "us", "eu", "edu", "gov", "mil", "int", "info", "biz", "name",
        "mobi", "asia", "cat", "coop", "jobs", "museum", "tel", "travel", "id", "in", "pl", "cz",
        "at", "be", "ie", "il", "mx", "ar", "cl", "za", "tr", "ua", "gr", "hu", "ro", "bg", "hr",
        "rs", "sk", "si", "lt", "lv", "ee", "design", "studio", "software", "cloud", " digital",
        "digital", "systems", "solutions", "team", "codes", "run", "build", "page", "site", "online",
        "store", "shop", "space", "fun", "live", "life", "world", "today", "network", "media", "one"
    ]

    private static let protectedGenericNames: Set<String> = [
        "accounts", "addressbook", "adobe", "amsdatamigratortool", "animoji", "antigravity", "apple",
        "application support", "arfilecache", "askpermission", "assistant", "audio", "audiodsp",
        "autosave information", "avatarkit", "baseband", "biome", "bluetooth", "bun", "byhost",
        "caches", "callhistorydb", "callhistorytransactions", "cargo", "categories", "cef",
        "chromium", "chronod", "claude", "claude-cli-nodejs", "clouddocs", "cloudkit",
        "cloudphotolibrary", "cocoapods", "code", "colorpickers", "colorsync", "compositorservices",
        "configurator", "containermanagerd", "containers", "contextstoreagent", "controlcenter",
        "cookies", "coreaccessories", "coreanalytics", "coreaudio", "coreavc", "corebluetooth",
        "corebrightness", "coredata", "coreduet", "corefollowup", "corehaptics", "coreidv",
        "corelocation", "coremedia", "coreml", "coremotion", "corerecipients", "coreservices",
        "corespeech", "corespotlight", "coretelephony", "coretext", "coretime", "coreui",
        "coreutils", "corevideo", "corewlan", "crashreporter", "cryptokit", "csdevkit", "cursor",
        "daemon", "data", "databases", "default", "developer", "devicecheck", "diagnosticreports",
        "diagnostics_agent", "differentialprivacy", "diskimages", "displayservices", "dmd",
        "docker", "dock", "donotdisturb", "dotnet", "duetexpertd", "electron", "energymodes",
        "ensemble", "exposurenotification", "extensionkit", "facetime", "familycircle",
        "familycircled", "featureflags", "feedback", "fileprovider", "fileproviderd", "finder",
        "findmy", "fitness", "focus", "fontcollections", "fontregistry", "fonts", "frameworks",
        "frontboard", "gamecenter", "gamecontroller", "gamekit", "games", "geod", "geoservices",
        "git", "github", "go", "go-build", "google", "gradle", "group containers", "health",
        "healthkit", "hearing", "help", "helper", "home", "homed", "homeenergyd", "homekit",
        "homebrew", "httpstorages", "icdd", "icloud", "identityservices", "ids", "imagent",
        "imageloader", "imcore", "imtransferagent", "inputmethodkit", "installcoordination",
        "intelligence", "intelligenceflow", "intelligenceplatform", "intents", "iosurface",
        "isolatedstorage", "itunes", "itunescloud", "jetbrains", "jetpackresourcebundles", "jna",
        "journal", "kbd", "keychains", "keyboard", "knowledge", "knowledge-agent",
        "knowledgestorage", "language", "launchagents", "launchdaemons", "launchservices", "llvm",
        "localauthentication", "localizationswitcherd", "locationaccessstored", "locationd",
        "lockdownmode", "loginwindow", "logs", "lsmimagecache", "mail", "managedconfiguration",
        "managedsettings", "mapkit", "maps", "mediaanalysis", "mediaanalysisd", "mediaremote",
        "mediaservices", "mediastream", "memorymaintenance", "messages", "metadata", "metal",
        "metalkit", "metalperformanceshaders", "metrickit", "microsoft", "microsoft devdiv", "midi",
        "mlcompute", "mobileactivation", "mobileasset", "mobilebackup", "mobilecontainers",
        "mobiledocuments", "mobileinstallation", "mobilekeybag", "mobilesync", "mobiletimer",
        "modelcatalog", "monoaibar", "monoclean", "monohub", "mononotch", "monopod", "monoshot",
        "monostats", "monotab", "monotile", "mozilla", "music", "musiclibrary", "nano",
        "naturallanguage", "nearbyinteraction", "nehelper", "network", "networkextension",
        "networkserviceproxy", "news", "node", "nodejs", "notes", "notificationcenter",
        "notifications", "nowplaying", "npm", "nuget", "openai", "oracle", "org.swift.swiftpm",
        "osanalytics", "oslog", "passbooks", "passd", "passes", "passkit", "passwords",
        "pasteboard", "pbs", "pdfkit", "pencilkit", "people", "personalization", "photoanalysis",
        "photolibrary", "photos", "pip", "pipx", "playwright", "pnpm", "podcasts", "powerlog",
        "powermanagement", "preferences", "preview", "printers", "printkit", "privacy",
        "privacypreservingmeasurement", "proactive", "proactiveeventtracker",
        "protectedcloudstorage", "proximity", "puppeteer", "pushkit", "python", "quartz",
        "quicklook", "quicklookthumbnailing", "rapport", "realitykit", "refsrcsymbols",
        "reminders", "replaykit", "ruby", "runningboard", "rust", "rustup", "safari",
        "safarishared", "safetykit", "sandbox", "saved application state", "scenekit",
        "screencapture", "screencapturekit", "screensavers", "screentime", "search", "searchparty",
        "security", "securityd", "sensorkit", "sentry", "sentrycrash", "sequoia", "services",
        "settings", "setupassistant", "shared", "sharedfilelist", "sharedfilelistd", "sharekit",
        "sharesheet", "sharing", "shazamkit", "shortcuts", "siri", "sirientitycache", "sirikit",
        "siritts", "sirittsservice", "siriuifoundation", "skylight", "sleep", "smartcardservices",
        "social", "softwareupdate", "soundanalysis", "speech", "speechrecognition", "spelling",
        "splashboard", "spotlight", "spritekit", "staged", "statuskit", "stocks", "storekit",
        "studentd", "suggestions", "swift", "swiftpm", "symbolication", "symbols",
        "symbolsourcesymbols", "symptomanalytics", "symptoms", "sync", "syncdefaultsd",
        "syncedpreferences", "system", "systemconfiguration", "systemextensions", "systempolicy",
        "systemstatus", "tailspin", "tcc", "telephonyutilities", "temp", "temporary",
        "temporaryitems", "textinput", "textrecognition", "texttospeech", "thermal",
        "threadnetwork", "time", "timemachine", "tips", "tokenbucketratelimiter", "translation",
        "translations", "trial", "triald", "trickplay", "trustd", "tv", "uifoundation", "uikit",
        "uniformtypeidentifiers", "universalaccess", "usage", "usagetracking", "useractivity",
        "usernotifications", "uv", "videosubscriptions", "videotoolbox", "virtualenv",
        "virtualization", "vision", "visionkit", "visualintelligence", "voicecontrol",
        "voicememos", "voices", "voiceshortcuts", "vscode", "wallet", "wallpaper", "watch",
        "watchconnectivity", "watchkit", "weather", "weatherkit", "webkit", "websitedata",
        "widgetkit", "wifi", "wifianalytics", "wifip2p", "wifipolicy", "wifivelocity",
        "windowserver", "workoutkit", "xpc", "xprotect", "yarn"
    ]

    struct Location: Sendable {
        let category: RemnantCategory
        let directory: URL
        let explanation: String
        let minimumSize: Int64
        let stripsExtension: String?
        let scanMode: OrphanScanMode
        let defaultSafety: CleanSafetyLevel

        init(
            category: RemnantCategory,
            directory: URL,
            explanation: String,
            minimumSize: Int64 = 1,
            stripsExtension: String? = nil,
            scanMode: OrphanScanMode = .bundleIdOnly,
            defaultSafety: CleanSafetyLevel = .safe
        ) {
            self.category = category
            self.directory = directory
            self.explanation = explanation
            self.minimumSize = minimumSize
            self.stripsExtension = stripsExtension
            self.scanMode = scanMode
            self.defaultSafety = defaultSafety
        }
    }

    static var locations: [Location] {
        let library = RemnantFinder.homeLibrary
        return [
            Location(
                category: .savedState,
                directory: library.appendingPathComponent("Saved Application State", isDirectory: true),
                explanation: localized("Saved window state from an app that is no longer installed"),
                minimumSize: 1,
                stripsExtension: "savedState",
                scanMode: .bundleIdOnly,
                defaultSafety: .safe
            ),
            Location(
                category: .containers,
                directory: library.appendingPathComponent("Containers", isDirectory: true),
                explanation: localized("Sandbox container with data from an app that is no longer installed"),
                minimumSize: 1024,
                stripsExtension: nil,
                scanMode: .bundleIdOnly,
                defaultSafety: .review
            ),
            Location(
                category: .webKit,
                directory: library.appendingPathComponent("WebKit", isDirectory: true),
                explanation: localized("WebKit data from an app that is no longer installed"),
                minimumSize: 1024,
                stripsExtension: nil,
                scanMode: .both,
                defaultSafety: .safe
            ),
            Location(
                category: .httpStorages,
                directory: library.appendingPathComponent("HTTPStorages", isDirectory: true),
                explanation: localized("Cookies and sessions from an app that is no longer installed"),
                minimumSize: 1024,
                stripsExtension: nil,
                scanMode: .both,
                defaultSafety: .safe
            ),
            Location(
                category: .applicationSupport,
                directory: library.appendingPathComponent("Application Support", isDirectory: true),
                explanation: localized("Application support data from an app that is no longer installed"),
                minimumSize: 1024,
                stripsExtension: nil,
                scanMode: .both,
                defaultSafety: .review
            ),
            Location(
                category: .caches,
                directory: library.appendingPathComponent("Caches", isDirectory: true),
                explanation: localized("Cache directory left by an app that is no longer installed"),
                minimumSize: 1024,
                stripsExtension: nil,
                scanMode: .both,
                defaultSafety: .safe
            ),
            Location(
                category: .preferences,
                directory: library.appendingPathComponent("Preferences", isDirectory: true),
                explanation: localized("Preferences file from an app that is no longer installed"),
                minimumSize: 64,
                stripsExtension: "plist",
                scanMode: .bundleIdOnly,
                defaultSafety: .review
            ),
            Location(
                category: .logs,
                directory: library.appendingPathComponent("Logs", isDirectory: true),
                explanation: localized("Log files left behind by an app that is no longer installed"),
                minimumSize: 1,
                stripsExtension: nil,
                scanMode: .both,
                defaultSafety: .safe
            ),
            Location(
                category: .launchAgents,
                directory: library.appendingPathComponent("LaunchAgents", isDirectory: true),
                explanation: localized("Background launch agent pointing to an uninstalled or missing application"),
                minimumSize: 1,
                stripsExtension: "plist",
                scanMode: .launchAgents,
                defaultSafety: .safe
            )
        ]
    }

    static var allowedRoots: [URL] {
        locations.map(\.directory)
    }

    static func isLikelyOrphan(
        identifier rawIdentifier: String,
        installed: InstalledAppIndex,
        isRegistered: (String) -> Bool
    ) -> Bool {
        guard PathSafety.isValidBundleIdentifier(rawIdentifier) else { return false }
        let identifier = rawIdentifier.lowercased()
        let components = identifier.split(separator: ".")
        guard components.count >= 3 else { return false }
        guard let tld = components.first, validReverseDNSTLDs.contains(String(tld)) else { return false }
        if protectedPrefixes.contains(where: identifier.hasPrefix) { return false }
        if components.prefix(2).contains(where: { protectedVendorComponents.contains(String($0)) }) { return false }
        if components.contains(where: { $0.contains("test") }) { return false }
        if installed.isRelated(to: identifier) { return false }
        if let appPart = components.last, installed.isNameRelated(to: String(appPart)) { return false }

        var candidate = rawIdentifier
        while candidate.split(separator: ".").count >= 3 {
            if isRegistered(candidate) { return false }
            guard let lastDot = candidate.lastIndex(of: ".") else { break }
            candidate = String(candidate[..<lastDot])
        }
        return true
    }

    static func isLikelyOrphanAppName(
        name rawName: String,
        installed: InstalledAppIndex
    ) -> Bool {
        guard PathSafety.isSafePathComponent(rawName) else { return false }
        guard rawName.count >= 3 && rawName.count <= 100 else { return false }
        let lower = rawName.lowercased()
        if protectedPrefixes.contains(where: lower.hasPrefix) { return false }
        if protectedGenericNames.contains(lower) { return false }
        if protectedVendorComponents.contains(lower) { return false }
        if lower.hasPrefix("mono") || lower.contains("test") { return false }
        if installed.isNameRelated(to: rawName) { return false }
        if installed.isRelated(to: lower) { return false }
        return true
    }

    static func inspectLaunchAgent(
        at url: URL,
        installed: InstalledAppIndex,
        isRegistered: (String) -> Bool = { _ in false }
    ) -> (isBroken: Bool, hint: String?) {
        guard let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            return (false, nil)
        }

        if let associated = plist["AssociatedBundleIdentifiers"] as? String {
            if !isLikelyOrphan(identifier: associated, installed: installed, isRegistered: isRegistered) {
                return (false, nil)
            }
        } else if let associatedList = plist["AssociatedBundleIdentifiers"] as? [String], !associatedList.isEmpty {
            if associatedList.contains(where: { !isLikelyOrphan(identifier: $0, installed: installed, isRegistered: isRegistered) }) {
                return (false, nil)
            }
        }

        let label = plist["Label"] as? String
        let args = plist["ProgramArguments"] as? [String] ?? []
        var programPath: String?
        if let direct = plist["Program"] as? String, !direct.isEmpty {
            programPath = direct
        } else if let first = args.first, !first.isEmpty {
            programPath = first
        }

        if let programPath {
            let expanded = NSString(string: programPath).expandingTildeInPath
            let wrappers: Set<String> = ["/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env", "/usr/bin/open"]
            if wrappers.contains(expanded), args.count > 1 {
                if let appArg = args.dropFirst().first(where: { $0.hasPrefix("/") || $0.hasPrefix("~") }) {
                    let expandedArg = NSString(string: appArg).expandingTildeInPath
                    if !FileManager.default.fileExists(atPath: expandedArg) {
                        let hint = label ?? (expandedArg as NSString).lastPathComponent
                        return (true, hint)
                    }
                    return (false, nil)
                }
                return (false, nil)
            }
            if FileManager.default.fileExists(atPath: expanded) {
                return (false, nil)
            } else {
                let hint = label ?? (expanded as NSString).lastPathComponent
                return (true, hint)
            }
        }

        if let label, PathSafety.isValidBundleIdentifier(label) {
            if isLikelyOrphan(identifier: label, installed: installed, isRegistered: isRegistered) {
                return (true, label)
            }
        }

        return (false, nil)
    }

    @MainActor
    static func runningIdentifiers() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    }

    @MainActor
    static func runningSnapshots() -> (identifiers: [String], names: [String]) {
        let running = NSWorkspace.shared.runningApplications
        let ids = running.compactMap(\.bundleIdentifier)
        let names = running.compactMap { $0.localizedName ?? $0.bundleURL?.deletingPathExtension().lastPathComponent }
        return (ids, names)
    }

    @concurrent
    static func scan(
        runningIdentifiers: [String] = [],
        runningNames: [String] = [],
        progress: ProgressReporter = .silent
    ) async -> [OrphanItem] {
        progress.report(ScanProgress(message: localized("Scanning installed applications…")), force: true)
        let installedApps = await AppScanner.scanInstalledApps(running: [])
        let env = InstalledAppIndex.activeSystemAndToolEnvironment()
        let index = InstalledAppIndex(
            identifiers: installedApps.map(\.bundleIdentifier) + runningIdentifiers + Array(env.identifiers),
            names: installedApps.map(\.name) + installedApps.map { $0.bundleURL.deletingPathExtension().lastPathComponent } + runningNames + Array(env.names),
            runningIdentifiers: runningIdentifiers + Array(env.identifiers),
            runningNames: runningNames + Array(env.names)
        )
        let workspace = NSWorkspace.shared
        let whitelist = WhitelistManager.shared
        let fileManager = FileManager.default

        struct Candidate: Sendable {
            let name: String
            let url: URL
            let location: Location
            let matchType: RemnantMatch
            let safetyLevel: CleanSafetyLevel
            let parentHint: String?
            let explanation: String
        }

        var candidates: [Candidate] = []
        for location in locations {
            if Task.isCancelled { return [] }
            progress.report(ScanProgress(message: localized("Checking %@…", location.directory.lastPathComponent)))
            guard let names = try? fileManager.contentsOfDirectory(atPath: location.directory.path) else { continue }
            for name in names {
                var candidateName = name
                if let ext = location.stripsExtension {
                    guard (name as NSString).pathExtension == ext else { continue }
                    candidateName = (name as NSString).deletingPathExtension
                }
                guard let url = PathSafety.child(named: name, of: location.directory) else { continue }
                guard !whitelist.blocksRemoval(of: url.path) else { continue }
                guard PathSafety.isAccessibleAndDeletable(url) else { continue }

                switch location.scanMode {
                case .bundleIdOnly:
                    let isOrphan = isLikelyOrphan(identifier: candidateName, installed: index) { id in
                        workspace.urlForApplication(withBundleIdentifier: id) != nil
                    }
                    if isOrphan {
                        candidates.append(Candidate(
                            name: candidateName,
                            url: url,
                            location: location,
                            matchType: .bundleIdentifier,
                            safetyLevel: location.defaultSafety,
                            parentHint: candidateName,
                            explanation: location.explanation
                        ))
                    }
                case .both:
                    if PathSafety.isValidBundleIdentifier(candidateName) {
                        let isOrphan = isLikelyOrphan(identifier: candidateName, installed: index) { id in
                            workspace.urlForApplication(withBundleIdentifier: id) != nil
                        }
                        if isOrphan {
                            candidates.append(Candidate(
                                name: candidateName,
                                url: url,
                                location: location,
                                matchType: .bundleIdentifier,
                                safetyLevel: location.defaultSafety,
                                parentHint: candidateName,
                                explanation: location.explanation
                            ))
                        }
                    } else if isLikelyOrphanAppName(name: candidateName, installed: index) {
                        let explanation = localized("Data for application “%@”, which is no longer installed", candidateName)
                        candidates.append(Candidate(
                            name: candidateName,
                            url: url,
                            location: location,
                            matchType: .appName,
                            safetyLevel: location.defaultSafety,
                            parentHint: candidateName,
                            explanation: explanation
                        ))
                    }
                case .launchAgents:
                    let (broken, hint) = inspectLaunchAgent(at: url, installed: index) { id in
                        workspace.urlForApplication(withBundleIdentifier: id) != nil
                    }
                    if broken {
                        let explanation = localized("Background agent pointing to an uninstalled or missing binary")
                        candidates.append(Candidate(
                            name: name,
                            url: url,
                            location: location,
                            matchType: .launchAgent,
                            safetyLevel: .safe,
                            parentHint: hint,
                            explanation: explanation
                        ))
                    }
                }
            }
        }

        let total = candidates.count
        let sizes = await DirectorySize.allocatedSizes(of: candidates.map(\.url)) { done in
            progress.report(ScanProgress(message: localized("Calculating sizes…"), completed: done, total: total))
        }
        if Task.isCancelled { return [] }

        return candidates.compactMap { candidate in
            let size = sizes[candidate.url] ?? 0
            guard size >= candidate.location.minimumSize else { return nil }
            return OrphanItem(
                name: candidate.name,
                category: candidate.location.category,
                url: candidate.url,
                size: size,
                explanation: candidate.explanation,
                matchType: candidate.matchType,
                safetyLevel: candidate.safetyLevel,
                parentAppHint: candidate.parentHint,
                isSelected: false
            )
        }
        .sorted { $0.size > $1.size }
    }
}
