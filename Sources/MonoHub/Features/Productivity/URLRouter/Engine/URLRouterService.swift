import Foundation
import AppKit
import CoreServices
import Observation

enum URLRoutingAction: Equatable, Sendable {
    case nativeApp(URL)
    case browser(bundleID: String, url: URL)
    case unhandled(URL)
}

@Observable
@MainActor
final class URLRouterService: NSObject {
    static let shared = URLRouterService()

    private(set) var installedBrowsers: [InstalledBrowser] = []
    private(set) var isDefaultBrowser: Bool = false
    var defaultBrowserBundleID: String = "com.apple.Safari" {
        didSet { savePreferences() }
    }
    var stripTrackers: Bool = true {
        didSet { savePreferences() }
    }
    var routeMeetingLinks: Bool = true {
        didSet { savePreferences() }
    }
    var rules: [URLRoutingRule] = [] {
        didSet { savePreferences() }
    }

    @ObservationIgnored private var isListeningAppleEvents = false
    @ObservationIgnored private var lastHandledURLString: String?
    @ObservationIgnored private var lastHandledTimestamp: Date = .distantPast

    private static let rulesDefaultsKey = "MonoHub_URLRouter_Rules"
    private static let stripTrackersDefaultsKey = "MonoHub_URLRouter_StripTrackers"
    private static let meetingLinksDefaultsKey = "MonoHub_URLRouter_MeetingLinks"
    private static let defaultBrowserDefaultsKey = "MonoHub_URLRouter_DefaultBrowser"

    override init() {
        super.init()
        loadPreferences()
        refreshInstalledBrowsers()
    }

    func start() {
        refreshInstalledBrowsers()
        checkDefaultBrowserStatus()
        registerAppleEventHandler()
    }

    func stop() {
        unregisterAppleEventHandler()
    }

    func refreshInstalledBrowsers() {
        guard !AppInfo.isRunningTests else {
            installedBrowsers = [
                InstalledBrowser(name: "Safari", bundleID: "com.apple.Safari", appURL: URL(fileURLWithPath: "/Applications/Safari.app"), isDefault: true),
                InstalledBrowser(name: "Helium", bundleID: "net.imput.helium", appURL: URL(fileURLWithPath: "/Applications/Helium.app"), isDefault: false)
            ]
            return
        }

        guard let testURL = URL(string: "https://apple.com") else { return }
        let currentDefaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: testURL)
        let currentDefaultBundleID = currentDefaultAppURL.flatMap { Bundle(url: $0)?.bundleIdentifier }

        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: testURL)
        var browsers: [InstalledBrowser] = []

        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL),
                  let bundleID = bundle.bundleIdentifier else { continue }

            if bundleID == AppInfo.bundleId {
                continue
            }

            let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.infoDictionary?["CFBundleName"] as? String
                ?? appURL.deletingPathExtension().lastPathComponent

            let isDef = (bundleID == currentDefaultBundleID)
            browsers.append(InstalledBrowser(name: name, bundleID: bundleID, appURL: appURL, isDefault: isDef))
        }

        var seen = Set<String>()
        self.installedBrowsers = browsers.filter { seen.insert($0.bundleID).inserted }

        if defaultBrowserBundleID.isEmpty || (!installedBrowsers.contains(where: { $0.bundleID == defaultBrowserBundleID }) && !installedBrowsers.isEmpty) {
            if let def = installedBrowsers.first(where: { $0.isDefault }) ?? installedBrowsers.first {
                defaultBrowserBundleID = def.bundleID
            }
        }

        checkDefaultBrowserStatus()
    }

    func checkDefaultBrowserStatus() {
        guard !AppInfo.isRunningTests else {
            isDefaultBrowser = false
            return
        }

        guard let testURL = URL(string: "https://apple.com"),
              let currentDefault = NSWorkspace.shared.urlForApplication(toOpen: testURL),
              let bundleID = Bundle(url: currentDefault)?.bundleIdentifier else {
            isDefaultBrowser = false
            return
        }

        isDefaultBrowser = (bundleID == AppInfo.bundleId)
    }

    func setAsDefaultBrowser() {
        guard !AppInfo.isRunningTests else {
            isDefaultBrowser = true
            return
        }

        let cfBundleID = AppInfo.bundleId as CFString
        LSSetDefaultHandlerForURLScheme("http" as CFString, cfBundleID)
        LSSetDefaultHandlerForURLScheme("https" as CFString, cfBundleID)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkDefaultBrowserStatus()
        }
    }

    func openSystemDefaultBrowserSettings() {
        guard !AppInfo.isRunningTests else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func resolveRouting(for rawURL: URL, sourceAppBundleID: String?) -> URLRoutingAction {

        let processedURL = stripTrackers ? TrackingParameterCleaner.clean(url: rawURL) : rawURL

        if routeMeetingLinks, let nativeURL = MeetingLinkRouter.rewriteIfSupported(url: processedURL) {
            return .nativeApp(nativeURL)
        }

        for rule in rules where rule.matches(url: processedURL, sourceApp: sourceAppBundleID) {
            return .browser(bundleID: rule.targetBrowserBundleID, url: processedURL)
        }

        let fallback = defaultBrowserBundleID.isEmpty ? "com.apple.Safari" : defaultBrowserBundleID
        return .browser(bundleID: fallback, url: processedURL)
    }

    func openURL(_ url: URL, sourceAppBundleID: String? = nil) {
        let action = resolveRouting(for: url, sourceAppBundleID: sourceAppBundleID)

        switch action {
        case .nativeApp(let nativeURL):
            if !AppInfo.isRunningTests {
                NSWorkspace.shared.open(nativeURL)
            }
        case .browser(let bundleID, let targetURL):
            openInBrowser(targetURL: targetURL, bundleID: bundleID)
        case .unhandled(let fallbackURL):
            if !AppInfo.isRunningTests {
                NSWorkspace.shared.open(fallbackURL)
            }
        }
    }

    private func openInBrowser(targetURL: URL, bundleID: String) {
        guard !AppInfo.isRunningTests else { return }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.promptsUserIfNeeded = false
            NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: config) { _, error in
                if error != nil {

                    NSWorkspace.shared.open(targetURL)
                }
            }
        } else {
            NSWorkspace.shared.open(targetURL)
        }
    }

    private func registerAppleEventHandler() {
        guard !isListeningAppleEvents, !AppInfo.isRunningTests else { return }
        isListeningAppleEvents = true

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    private func unregisterAppleEventHandler() {
        guard isListeningAppleEvents, !AppInfo.isRunningTests else { return }
        isListeningAppleEvents = false

        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        let now = Date()
        if lastHandledURLString == urlString && now.timeIntervalSince(lastHandledTimestamp) < 0.35 {
            return
        }
        lastHandledURLString = urlString
        lastHandledTimestamp = now

        var senderBundleID: String?
        if let pidNumber = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value {
            let app = NSRunningApplication(processIdentifier: pid_t(pidNumber))
            senderBundleID = app?.bundleIdentifier
        }

        if senderBundleID == nil {
            senderBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }

        openURL(url, sourceAppBundleID: senderBundleID)
    }

    func addRule(_ rule: URLRoutingRule) {
        rules.append(rule)
    }

    func updateRule(_ rule: URLRoutingRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        }
    }

    func removeRule(id: UUID) {
        rules.removeAll(where: { $0.id == id })
    }

    func toggleRule(id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].isEnabled.toggle()
        }
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Self.stripTrackersDefaultsKey) != nil {
            self.stripTrackers = defaults.bool(forKey: Self.stripTrackersDefaultsKey)
        }
        if defaults.object(forKey: Self.meetingLinksDefaultsKey) != nil {
            self.routeMeetingLinks = defaults.bool(forKey: Self.meetingLinksDefaultsKey)
        }
        if let savedBrowser = defaults.string(forKey: Self.defaultBrowserDefaultsKey) {
            self.defaultBrowserBundleID = savedBrowser
        }

        if let data = defaults.data(forKey: Self.rulesDefaultsKey),
           let decoded = try? JSONDecoder().decode([URLRoutingRule].self, from: data) {
            self.rules = decoded
        } else {

            self.rules = [
                URLRoutingRule(
                    name: "Slack Links no Helium",
                    isEnabled: true,
                    sourceAppBundleID: "com.tinyspeck.slackmacgap",
                    sourceAppName: "Slack",
                    domainPattern: "*",
                    targetBrowserBundleID: "net.imput.helium",
                    targetBrowserName: "Helium"
                ),
                URLRoutingRule(
                    name: "Google Meet no Chrome",
                    isEnabled: false,
                    sourceAppBundleID: nil,
                    sourceAppName: nil,
                    domainPattern: "meet.google.com",
                    targetBrowserBundleID: "com.google.Chrome",
                    targetBrowserName: "Google Chrome"
                )
            ]
        }
    }

    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(stripTrackers, forKey: Self.stripTrackersDefaultsKey)
        defaults.set(routeMeetingLinks, forKey: Self.meetingLinksDefaultsKey)
        defaults.set(defaultBrowserBundleID, forKey: Self.defaultBrowserDefaultsKey)

        if let encoded = try? JSONEncoder().encode(rules) {
            defaults.set(encoded, forKey: Self.rulesDefaultsKey)
        }
    }
}
