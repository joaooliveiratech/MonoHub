import Testing
import Foundation
import SwiftUI
@testable import MonoHub

@Suite("Teleprompter & Scratchpad Tests")
@MainActor
struct TeleprompterTests {

    @Test("TeleprompterScript word count and estimated reading time calculations")
    func scriptCalculations() {
        let original = Localization.language
        defer { Localization.language = original }
        Localization.language = .portuguese

        let emptyScript = TeleprompterScript(title: "Vazio", content: "")
        #expect(emptyScript.wordCount == 0)
        #expect(emptyScript.characterCount == 0)
        #expect(emptyScript.estimatedReadingSeconds == 0)
        #expect(emptyScript.previewSnippet == "Toque para adicionar roteiro ou notas")

        // 130 words corresponds to ~60s (1 min) of natural speaking pace
        let words = Array(repeating: "palavra", count: 130).joined(separator: " ")
        let script = TeleprompterScript(title: "Discurso", content: words)
        #expect(script.wordCount == 130)
        #expect(script.estimatedReadingSeconds == 60)
        #expect(script.formattedReadingTime == "1m de fala")

        let shortWords = Array(repeating: "tópico", count: 65).joined(separator: " ")
        let shortScript = TeleprompterScript(title: "Curto", content: shortWords)
        #expect(shortScript.wordCount == 65)
        #expect(shortScript.estimatedReadingSeconds == 30)
        #expect(shortScript.formattedReadingTime == "30s de fala")

        Localization.language = .english
        #expect(emptyScript.previewSnippet == "Tap to add script or notes")
        #expect(script.formattedReadingTime == "1m speech")
        #expect(shortScript.formattedReadingTime == "30s speech")
    }

    @Test("TeleprompterScript preview snippet extracts first non-empty lines")
    func scriptPreviewSnippet() {
        let multiline = """

        Primeira linha de abertura
        
        Segunda linha com tópicos centrais
        Terceira linha não deve aparecer na prévia
        """
        let script = TeleprompterScript(title: "Multi", content: multiline)
        #expect(script.previewSnippet == "Primeira linha de abertura • Segunda linha com tópicos centrais")
    }

    @Test("Teleprompter templates have valid non-empty content and metadata")
    func templatesVerification() {
        #expect(TeleprompterTemplate.allCases.count >= 4)
        for template in TeleprompterTemplate.allCases {
            #expect(!template.title.isEmpty)
            #expect(!template.iconName.isEmpty)
            #expect(!template.defaultContent.isEmpty)
            #expect(template.defaultContent.contains("["))
        }
    }

    @Test("TeleprompterManager speed and font size clamping")
    func managerSpeedAndFontClamping() {
        let suiteName = "com.antigravity.monohub.tests.teleprompter.clamping"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = TeleprompterManager(defaults: defaults)

        manager.speed = 35.0
        manager.adjustSpeed(by: 200.0)
        #expect(manager.speed == 120.0) // clamped to max 120

        manager.adjustSpeed(by: -300.0)
        #expect(manager.speed == 10.0) // clamped to min 10

        manager.fontSize = 16.0
        manager.adjustFontSize(by: 50.0)
        #expect(manager.fontSize == 28.0) // clamped to max 28

        manager.adjustFontSize(by: -50.0)
        #expect(manager.fontSize == 12.0) // clamped to min 12
    }

    @Test("TeleprompterManager script lifecycle and template application")
    func managerScriptLifecycle() {
        let suiteName = "com.antigravity.monohub.tests.teleprompter.lifecycle"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = TeleprompterManager(defaults: defaults)

        let initialCount = manager.scripts.count
        #expect(initialCount >= 1)

        let originalLang = Localization.language
        defer { Localization.language = originalLang }
        Localization.language = .portuguese

        // Create new script
        manager.createNewScript(title: "Pitch Q4", content: "Nosso produto inovador...")
        #expect(manager.scripts.count == initialCount + 1)
        #expect(manager.activeScript.title == "Pitch Q4")
        #expect(manager.activeScript.content == "Nosso produto inovador...")

        // Duplicate
        manager.duplicateActiveScript()
        #expect(manager.scripts.count == initialCount + 2)
        #expect(manager.activeScript.title.contains("Cópia"))

        // Update active content
        manager.updateActiveContent("Novo conteúdo atualizado")
        #expect(manager.activeScript.content == "Novo conteúdo atualizado")

        // Apply template creates a new script when current has content
        manager.applyTemplate(.oneOnOne)
        #expect(manager.activeScript.title == TeleprompterTemplate.oneOnOne.title)
        #expect(manager.activeScript.content.contains("1:1"))

        // Delete script
        let toDeleteID = manager.activeScriptID
        manager.deleteScript(id: toDeleteID)
        #expect(!manager.scripts.contains(where: { $0.id == toDeleteID }))
    }

    @Test("TeleprompterManager playback controls and rewind")
    func managerPlaybackControls() {
        let suiteName = "com.antigravity.monohub.tests.teleprompter.playback"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = TeleprompterManager(defaults: defaults)

        #expect(!manager.isPlaying)
        manager.play()
        #expect(manager.isPlaying)

        manager.pause()
        #expect(!manager.isPlaying)

        manager.togglePlayPause()
        #expect(manager.isPlaying)

        manager.scrubTo(offset: 45.0)
        #expect(manager.scrollOffset >= 0)

        manager.rewind()
        #expect(!manager.isPlaying)
        #expect(manager.scrollOffset == 0)
        #expect(manager.elapsedTime == 0)
    }

    @Test("NotchPreferences teleprompter integration and engine demand")
    func preferencesTeleprompterIntegration() {
        let suiteName = "com.antigravity.monohub.tests.teleprompter.prefs"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = NotchPreferences(defaults: defaults)
        #expect(prefs.enableTeleprompterModule == true)
        #expect(prefs.showHomeTeleprompterCard == true)
        #expect(prefs.isTabEnabled(.teleprompter) == true)
        #expect(prefs.isHomeCardEnabled(.teleprompter) == true)
        #expect(prefs.engineDemand.teleprompter == true)

        prefs.enableTeleprompterModule = false
        #expect(prefs.isTabEnabled(.teleprompter) == false)
        #expect(prefs.availableTabs.contains(.teleprompter) == false)

        prefs.showHomeTeleprompterCard = false
        #expect(prefs.isHomeCardVisible(.teleprompter) == false)
        #expect(prefs.engineDemand.teleprompter == false)

        prefs.resetToDefaults()
        #expect(prefs.enableTeleprompterModule == true)
        #expect(prefs.showHomeTeleprompterCard == true)
        #expect(prefs.teleprompterSpeed == 35.0)
        #expect(prefs.teleprompterFontSize == 16.0)
        #expect(prefs.teleprompterShowFocusGuide == true)
        #expect(prefs.teleprompterKeepOpenWhilePlaying == true)
        #expect(prefs.teleprompterIsMirrored == false)

        let manager = TeleprompterManager(defaults: defaults)
        #expect(manager.isCameraEnabled == true)
        #expect(manager.cameraDimming == 0.45)
        manager.isCameraEnabled = false
        #expect(manager.isCameraEnabled == false)
    }
}
