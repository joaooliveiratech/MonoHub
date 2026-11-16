import Foundation
import Testing
@testable import MonoHub

@Suite("Screenshot localization")
@MainActor
struct ScreenshotLocalizationTests {
    @Test("ShotText follows the MonoHub language")
    func followsHubLanguage() {
        let original = Localization.language
        defer { Localization.language = original }

        Localization.language = .english
        #expect(ShotText.tabGeneral == "General")
        #expect(ShotText.hexCopiedFeedback(hex: "#FFFFFF") == "HEX Copied: #FFFFFF")
        #expect(ShotText.copyButtonTitle == "Copy")
        #expect(ShotText.menuCaptureArea == "Capture Area")

        Localization.language = .portuguese
        #expect(ShotText.tabGeneral == "Geral")
        #expect(ShotText.hexCopiedFeedback(hex: "#FFFFFF") == "HEX Copiado: #FFFFFF")
        #expect(ShotText.copyButtonTitle == "Copiar")
        #expect(ShotText.menuCaptureArea == "Capturar Área")
    }

    @Test("Capture request titles change with the language")
    func captureTitlesTranslate() {
        let original = Localization.language
        defer { Localization.language = original }

        for request in CaptureRequest.allCases {
            Localization.language = .english
            let english = [request.menuTitle, request.settingsTitle, request.settingsSubtitle]
            Localization.language = .portuguese
            let portuguese = [request.menuTitle, request.settingsTitle, request.settingsSubtitle]
            for (en, pt) in zip(english, portuguese) {
                #expect(en != pt, "\(en) is not translated")
            }
        }
    }
}
