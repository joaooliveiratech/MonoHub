import AppKit
import Carbon
import Foundation
import Testing
@testable import MonoHub

@Suite("Shortcuts & Preferences")
@MainActor
struct ShortcutAndPreferencesTests {
    private func isolatedDefaults(_ suffix: String = "main") -> UserDefaults {
        let suite = "com.antigravity.monohub.tests.screenshot.\(suffix)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Rejects global shortcuts that only use Shift")
    func shiftOnlyShortcutIsInvalid() {
        #expect(!KeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(shiftKey)).isValidGlobalShortcut)
        #expect(!KeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0).isValidGlobalShortcut)
        #expect(KeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey)).isValidGlobalShortcut)
        #expect(KeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | shiftKey)).isValidGlobalShortcut)
    }

    @Test("Accepts the A key, whose virtual key code is zero")
    func keyCodeZeroIsAValidShortcut() {
        let shortcut = KeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | shiftKey))
        #expect(shortcut.isValidGlobalShortcut)
        #expect(shortcut.displayString == "⇧⌘A")
    }

    @Test("Names special and function keys without a keyboard-layout lookup")
    func specialKeyNames() {
        #expect(KeyShortcut.keyName(for: UInt32(kVK_F5)) == "F5")
        #expect(KeyShortcut.keyName(for: UInt32(kVK_Return)) == "↩")
        #expect(KeyShortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | optionKey | controlKey)).modifierSymbols == "⌃⌥⌘")
    }

    @Test("Builds menu key equivalents that match the configured shortcut")
    func menuKeyEquivalents() {
        #expect(KeyShortcut.defaultArea.menuKeyEquivalent == "1")
        #expect(KeyShortcut.defaultOCR.menuKeyEquivalent == "o")
        #expect(KeyShortcut.defaultOCR.cocoaModifiers == [.command, .shift])

        let f3 = KeyShortcut(keyCode: UInt32(kVK_F3), modifiers: UInt32(cmdKey))
        #expect(f3.menuKeyEquivalent == String(Character(UnicodeScalar(UInt32(NSF3FunctionKey))!)))
    }

    @Test("Round-trips shortcuts through Carbon and Cocoa modifier flags")
    func modifierRoundTrip() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let carbon = KeyShortcut.carbonModifiers(from: flags)
        #expect(KeyShortcut(keyCode: 0, modifiers: carbon).cocoaModifiers == flags)
    }

    @Test("Persists shortcuts and detects conflicts between captures")
    func shortcutPersistence() {
        let defaults = isolatedDefaults()
        let preferences = ScreenshotPreferences(defaults: defaults)

        let custom = KeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | optionKey))
        preferences.setShortcut(custom, for: .area)
        #expect(preferences.request(using: custom, excluding: .window) == .area)
        #expect(preferences.request(using: custom, excluding: .area) == nil)

        let reloaded = ScreenshotPreferences(defaults: defaults)
        #expect(reloaded.shortcut(for: .area) == custom)
        #expect(reloaded.shortcut(for: .fullscreen) == .defaultFullscreen)

        preferences.resetShortcutsToDefaults()
        #expect(ScreenshotPreferences(defaults: defaults).shortcut(for: .area) == .defaultArea)
    }

    @Test("Ignores stored shortcuts that would hijack typing")
    func invalidStoredShortcutFallsBack() throws {
        let defaults = isolatedDefaults()
        let hijacking = KeyShortcut(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(shiftKey))
        defaults.set(try JSONEncoder().encode(hijacking), forKey: CaptureRequest.area.preferencesKey)

        #expect(ScreenshotPreferences(defaults: defaults).shortcut(for: .area) == .defaultArea)
    }

    @Test("Clamps a corrupted JPEG quality")
    func sanitisesStoredValues() {
        let defaults = isolatedDefaults()
        defaults.set(7.0, forKey: "MonoHub_Screenshot_jpegQuality")

        #expect(ScreenshotPreferences(defaults: defaults).jpegQuality == 1.0)
    }

    @Test("Imports the standalone MonoShot settings once")
    func importsLegacyDomain() throws {
        let defaults = isolatedDefaults("main")
        let legacy = isolatedDefaults("legacy")
        legacy.set(0.6, forKey: "jpegQuality")
        legacy.set(false, forKey: "playShutterSound")
        legacy.set("jpeg", forKey: "defaultExportFormat")
        let custom = KeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | optionKey))
        legacy.set(try JSONEncoder().encode(custom), forKey: CaptureRequest.area.legacyPreferencesKey)

        let imported = ScreenshotPreferences(defaults: defaults, legacyDefaults: legacy)
        #expect(imported.jpegQuality == 0.6)
        #expect(imported.playShutterSound == false)
        #expect(imported.defaultExportFormat == .jpeg)
        #expect(imported.shortcut(for: .area) == custom)

        legacy.set(0.9, forKey: "jpegQuality")
        #expect(ScreenshotPreferences(defaults: defaults, legacyDefaults: legacy).jpegQuality == 0.6)
    }

    @Test("Falls back to Pictures when the remembered folder no longer exists")
    func missingSaveFolderFallsBack() {
        let preferences = ScreenshotPreferences(defaults: isolatedDefaults())
        preferences.saveLocationMode = .custom
        preferences.customSaveDirectory = "/nonexistent/\(UUID().uuidString)"
        #expect(preferences.effectiveSaveDirectory != preferences.customSaveDirectory)
        #expect(FileManager.default.fileExists(atPath: preferences.effectiveSaveDirectory))
    }

    @Test("Persists the menu bar icon preference")
    func menuBarVisibilityPersists() {
        let defaults = isolatedDefaults()
        ScreenshotPreferences(defaults: defaults).showMenuBarIcon = false
        #expect(ScreenshotPreferences(defaults: defaults).showMenuBarIcon == false)
    }

    @Test("Every capture request has a distinct default shortcut and storage key")
    func captureRequestDefaultsAreDistinct() {
        let shortcuts = Set(CaptureRequest.allCases.map(\.defaultShortcut))
        let keys = Set(CaptureRequest.allCases.map(\.preferencesKey))
        #expect(shortcuts.count == CaptureRequest.allCases.count)
        #expect(keys.count == CaptureRequest.allCases.count)
        #expect(Set(CaptureRequest.allCases.map(\.urlCommand)).count == CaptureRequest.allCases.count)
        #expect(CaptureRequest.allCases.allSatisfy { $0.defaultShortcut.isValidGlobalShortcut })
    }
}
