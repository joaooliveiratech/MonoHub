import Foundation
import Testing
@testable import MonoHub

@Suite("Localization")
struct LocalizationTests {
    private static let identicalInPortuguese: Set<String> = [
        "Apps", "Normal", "Tiler", "Swap", "SSD", "CPU", "RAM", "GPU", "Chip",
        "Download %@/s", "Upload %@/s", "Download %@/s, upload %@/s"
    ]

    private static func sourceKeys() throws -> Set<String> {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let pattern = try NSRegularExpression(pattern: #"localized\(\s*"((?:[^"\\]|\\.)*)"(?:\s*,\s*context:\s*"([^"]+)")?"#)
        let ternary = try NSRegularExpression(pattern: #"localized\([^"\n]*\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)""#)
        var keys = Set<String>()
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !["PortugueseStrings.swift", "Localization.swift"].contains($0.lastPathComponent) } ?? []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                let key = String(text[keyRange])
                if let contextRange = Range(match.range(at: 2), in: text) {
                    keys.insert("\(text[contextRange]):\(key)")
                } else {
                    keys.insert(key)
                }
            }
            for match in ternary.matches(in: text, range: range) {
                for group in 1...2 {
                    if let keyRange = Range(match.range(at: group), in: text) {
                        keys.insert(String(text[keyRange]))
                    }
                }
            }
        }
        return keys
    }

    @Test("English is the default language")
    func defaultLanguage() {
        #expect(Localization.string("Battery", in: .english) == "Battery")
        #expect(AppLanguage(rawValue: "unknown") == nil)
        #expect(AppLanguage.allCases.first == .english)
    }

    @Test("Every string shown in the UI has a Portuguese translation")
    func everyKeyTranslated() throws {
        let keys = try Self.sourceKeys()
        #expect(keys.count > 150)
        let missing = keys.subtracting(Localization.portuguese.keys).subtracting(Self.identicalInPortuguese)
        #expect(missing.isEmpty, "Missing Portuguese: \(missing.sorted())")
    }

    @Test("The Portuguese table has no unused entries")
    func noUnusedTranslations() throws {
        let keys = try Self.sourceKeys()
        let unused = Set(Localization.portuguese.keys).subtracting(keys)
        #expect(unused.isEmpty, "Unused Portuguese: \(unused.sorted())")
    }

    @Test("Translations keep the same format placeholders")
    func placeholdersMatch() throws {
        let placeholder = try NSRegularExpression(pattern: "%(?:@|d|%)")
        func placeholders(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        }
        for (english, portuguese) in Localization.portuguese {
            #expect(placeholders(english) == placeholders(portuguese), "\(english) → \(portuguese)")
        }
    }

    @Test("Portuguese lookups resolve, including gendered context")
    func portugueseLookups() {
        #expect(Localization.string("Battery", in: .portuguese) == "Bateria")
        #expect(Localization.string("Charging on Hold", in: .portuguese) == "Carga em espera")
        #expect(Localization.string("pressure:Critical", in: .portuguese) == "Crítica")
        #expect(Localization.string("Critical", in: .portuguese) == "Crítico")
        #expect(Localization.string("Untranslated text", in: .portuguese) == "Untranslated text")
        #expect(AppLanguage.portuguese.locale.decimalSeparator == ",")
        #expect(AppLanguage.english.locale.decimalSeparator == ".")
    }
}
