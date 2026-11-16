import Foundation
import AppKit

nonisolated struct SnippetItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var keyword: String
    var content: String
    var label: String
    var isEnabled: Bool
    var dateCreated: Date

    init(
        id: UUID = UUID(),
        keyword: String,
        content: String,
        label: String,
        isEnabled: Bool = true,
        dateCreated: Date = Date()
    ) {
        self.id = id
        self.keyword = keyword
        self.content = content
        self.label = label
        self.isEnabled = isEnabled
        self.dateCreated = dateCreated
    }

    func evaluatedContent() -> String {
        SnippetTokenEvaluator.evaluate(content)
    }
}

nonisolated enum SnippetTokenEvaluator: Sendable {
    static func evaluate(_ template: String) -> String {
        var result = template

        if result.contains("{date}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy"
            result = result.replacingOccurrences(of: "{date}", with: formatter.string(from: Date()))
        }

        if result.contains("{time}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            result = result.replacingOccurrences(of: "{time}", with: formatter.string(from: Date()))
        }

        if result.contains("{datetime}") {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
            result = result.replacingOccurrences(of: "{datetime}", with: formatter.string(from: Date()))
        }

        if result.contains("{uuid}") {
            result = result.replacingOccurrences(of: "{uuid}", with: UUID().uuidString.lowercased())
        }

        if result.contains("{clipboard}") {
            let clipText: String
            if !AppInfo.isRunningTests {
                clipText = NSPasteboard.general.string(forType: .string) ?? ""
            } else {
                clipText = "clipboard_mock"
            }
            result = result.replacingOccurrences(of: "{clipboard}", with: clipText)
        }

        return result
    }
}
