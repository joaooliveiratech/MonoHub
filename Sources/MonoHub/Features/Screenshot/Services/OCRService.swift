import CoreGraphics
import Foundation
import Vision

nonisolated final class OCRService: Sendable {
    static let shared = OCRService()

    private static let languages = [
        Locale.Language(identifier: "pt-BR"),
        Locale.Language(identifier: "en-US"),
        Locale.Language(identifier: "es-ES")
    ]

    private init() {}

    @concurrent
    func recognizeText(from image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = Self.languages

        let observations = try await request.perform(on: image)

        return observations
            .sorted { lhs, rhs in
                if abs(lhs.topLeft.y - rhs.topLeft.y) > 0.008 {
                    return lhs.topLeft.y > rhs.topLeft.y
                }
                return lhs.topLeft.x < rhs.topLeft.x
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    @MainActor
    func recognizeAndCopy(from image: CGImage, concealed: Bool) async throws -> String {
        let text = try await recognizeText(from: image)
        guard !text.isEmpty else { return text }
        PasteboardWriter.write(text: text, concealed: concealed)
        return text
    }
}
