import Foundation
import Observation

enum SaveLocationMode: String, CaseIterable, Identifiable, Sendable {
    case lastUsed = "lastUsed"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lastUsed: return ShotText.saveLocationLastUsed
        case .custom: return ShotText.saveLocationCustom
        }
    }
}

@Observable
final class ScreenshotPreferences {
    static let shared = makeShared()

    static let legacyDomain = "com.antigravity.monoshot"
    static let jpegQualityRange: ClosedRange<Double> = 0.5...1.0

    private enum Key {
        static let copyToClipboardAfterCapture = "MonoHub_Screenshot_copyToClipboardAfterCapture"
        static let openEditorAfterCapture = "MonoHub_Screenshot_openEditorAfterCapture"
        static let playShutterSound = "MonoHub_Screenshot_playShutterSound"
        static let concealRecognizedText = "MonoHub_Screenshot_concealRecognizedText"
        static let saveLocationMode = "MonoHub_Screenshot_saveLocationMode"
        static let customSaveDirectory = "MonoHub_Screenshot_customSaveDirectory"
        static let lastUsedSaveDirectory = "MonoHub_Screenshot_lastUsedSaveDirectory"
        static let defaultExportFormat = "MonoHub_Screenshot_defaultExportFormat"
        static let showMenuBarIcon = "MonoHub_Screenshot_showMenuBarIcon"
        static let jpegQuality = "MonoHub_Screenshot_jpegQuality"
        static let downscaleRetina = "MonoHub_Screenshot_downscaleRetina"
        static let legacyMigrated = "MonoHub_Screenshot_legacyMigrated"

        static let legacyKeys: [(old: String, new: String)] = [
            ("copyToClipboardAfterCapture", copyToClipboardAfterCapture),
            ("openEditorAfterCapture", openEditorAfterCapture),
            ("playShutterSound", playShutterSound),
            ("concealRecognizedText", concealRecognizedText),
            ("saveLocationMode", saveLocationMode),
            ("customSaveDirectory", customSaveDirectory),
            ("lastUsedSaveDirectory", lastUsedSaveDirectory),
            ("defaultExportFormat", defaultExportFormat),
            ("showMenuBarIcon", showMenuBarIcon),
            ("jpegQuality", jpegQuality),
            ("downscaleRetina", downscaleRetina)
        ]
    }

    @ObservationIgnored private let defaults: UserDefaults

    var copyToClipboardAfterCapture: Bool {
        didSet { defaults.set(copyToClipboardAfterCapture, forKey: Key.copyToClipboardAfterCapture) }
    }

    var openEditorAfterCapture: Bool {
        didSet { defaults.set(openEditorAfterCapture, forKey: Key.openEditorAfterCapture) }
    }

    var playShutterSound: Bool {
        didSet { defaults.set(playShutterSound, forKey: Key.playShutterSound) }
    }

    var concealRecognizedText: Bool {
        didSet { defaults.set(concealRecognizedText, forKey: Key.concealRecognizedText) }
    }

    var saveLocationMode: SaveLocationMode {
        didSet { defaults.set(saveLocationMode.rawValue, forKey: Key.saveLocationMode) }
    }

    var customSaveDirectory: String {
        didSet { defaults.set(customSaveDirectory, forKey: Key.customSaveDirectory) }
    }

    var lastUsedSaveDirectory: String {
        didSet { defaults.set(lastUsedSaveDirectory, forKey: Key.lastUsedSaveDirectory) }
    }

    var defaultExportFormat: ExportFormat {
        didSet { defaults.set(defaultExportFormat.rawValue, forKey: Key.defaultExportFormat) }
    }

    var jpegQuality: Double {
        didSet { defaults.set(jpegQuality, forKey: Key.jpegQuality) }
    }

    var downscaleRetina: Bool {
        didSet { defaults.set(downscaleRetina, forKey: Key.downscaleRetina) }
    }

    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }

    private(set) var shortcuts: [CaptureRequest: KeyShortcut] {
        didSet {
            guard shortcuts != oldValue else { return }
            for (request, shortcut) in shortcuts where oldValue[request] != shortcut {
                if let data = try? JSONEncoder().encode(shortcut) {
                    defaults.set(data, forKey: request.preferencesKey)
                }
            }
        }
    }

    func shortcut(for request: CaptureRequest) -> KeyShortcut {
        shortcuts[request] ?? request.defaultShortcut
    }

    func setShortcut(_ shortcut: KeyShortcut, for request: CaptureRequest) {
        shortcuts[request] = shortcut
    }

    func request(using shortcut: KeyShortcut, excluding excluded: CaptureRequest) -> CaptureRequest? {
        CaptureRequest.allCases.first { $0 != excluded && self.shortcut(for: $0) == shortcut }
    }

    func resetShortcutsToDefaults() {
        shortcuts = Dictionary(uniqueKeysWithValues: CaptureRequest.allCases.map { ($0, $0.defaultShortcut) })
    }

    var effectiveSaveDirectory: String {
        let path = saveLocationMode == .custom ? customSaveDirectory : lastUsedSaveDirectory
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return path
        }
        return Self.picturesDirectory
    }

    func updateLastSaveDirectory(_ path: String) {
        guard path != lastUsedSaveDirectory else { return }
        lastUsedSaveDirectory = path
    }

    private static var picturesDirectory: String {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
    }

    init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        Self.importLegacyValues(from: legacyDefaults, into: defaults)

        self.copyToClipboardAfterCapture = defaults.object(forKey: Key.copyToClipboardAfterCapture) as? Bool ?? true
        self.openEditorAfterCapture = defaults.object(forKey: Key.openEditorAfterCapture) as? Bool ?? true
        self.playShutterSound = defaults.object(forKey: Key.playShutterSound) as? Bool ?? true
        self.concealRecognizedText = defaults.object(forKey: Key.concealRecognizedText) as? Bool ?? true
        self.showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true

        let initialDirectory = Self.picturesDirectory
        let modeRaw = defaults.string(forKey: Key.saveLocationMode) ?? SaveLocationMode.lastUsed.rawValue
        self.saveLocationMode = SaveLocationMode(rawValue: modeRaw) ?? .lastUsed
        self.customSaveDirectory = defaults.string(forKey: Key.customSaveDirectory) ?? initialDirectory
        self.lastUsedSaveDirectory = defaults.string(forKey: Key.lastUsedSaveDirectory) ?? initialDirectory

        let formatRaw = defaults.string(forKey: Key.defaultExportFormat) ?? ExportFormat.png.rawValue
        self.defaultExportFormat = ExportFormat(rawValue: formatRaw) ?? .png

        let storedQuality = defaults.object(forKey: Key.jpegQuality) as? Double ?? 0.85
        self.jpegQuality = min(Self.jpegQualityRange.upperBound, max(Self.jpegQualityRange.lowerBound, storedQuality))
        self.downscaleRetina = defaults.bool(forKey: Key.downscaleRetina)

        self.shortcuts = Dictionary(uniqueKeysWithValues: CaptureRequest.allCases.map { request in
            (request, Self.loadShortcut(from: defaults, request: request))
        })
    }

    private static func importLegacyValues(from legacy: UserDefaults?, into defaults: UserDefaults) {
        guard let legacy, !defaults.bool(forKey: Key.legacyMigrated) else { return }
        defaults.set(true, forKey: Key.legacyMigrated)

        for (oldKey, newKey) in Key.legacyKeys where defaults.object(forKey: newKey) == nil {
            if let value = legacy.object(forKey: oldKey) {
                defaults.set(value, forKey: newKey)
            }
        }
        for request in CaptureRequest.allCases where defaults.object(forKey: request.preferencesKey) == nil {
            if let data = legacy.data(forKey: request.legacyPreferencesKey) {
                defaults.set(data, forKey: request.preferencesKey)
            }
        }
    }

    private static func loadShortcut(from defaults: UserDefaults, request: CaptureRequest) -> KeyShortcut {
        guard let data = defaults.data(forKey: request.preferencesKey),
              let decoded = try? JSONDecoder().decode(KeyShortcut.self, from: data),
              decoded.isValidGlobalShortcut else {
            return request.defaultShortcut
        }
        return decoded
    }
}

extension ScreenshotPreferences {
    static func makeShared() -> ScreenshotPreferences {
        ScreenshotPreferences(defaults: .standard, legacyDefaults: UserDefaults(suiteName: legacyDomain))
    }
}
