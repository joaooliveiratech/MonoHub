import Foundation

struct TeleprompterScript: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = localized("New Script"),
        content: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.updatedAt = updatedAt
    }

    var wordCount: Int {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    var characterCount: Int {
        content.count
    }

    var estimatedReadingSeconds: Int {
        let words = wordCount
        guard words > 0 else { return 0 }
        return max(1, Int(round(Double(words) / 130.0 * 60.0)))
    }

    var formattedReadingTime: String {
        let secs = estimatedReadingSeconds
        if secs < 60 {
            return localized("%ds speech", secs)
        } else {
            let mins = secs / 60
            let remSecs = secs % 60
            return remSecs > 0 ? localized("%dm %ds speech", mins, remSecs) : localized("%dm speech", mins)
        }
    }

    var previewSnippet: String {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.isEmpty {
            return localized("Tap to add script or notes")
        }
        return lines.prefix(2).joined(separator: " • ")
    }
}

enum TeleprompterMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case reading = "reading"
    case editing = "editing"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reading: return localized("Reading")
        case .editing: return localized("Edit")
        }
    }

    var iconName: String {
        switch self {
        case .reading: return "play.rectangle.fill"
        case .editing: return "square.and.pencil"
        }
    }
}

enum TeleprompterTemplate: String, CaseIterable, Identifiable, Sendable {
    case oneOnOne = "oneOnOne"
    case pitch = "pitch"
    case clientMeeting = "clientMeeting"
    case videoScript = "videoScript"
    case quickNotes = "quickNotes"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneOnOne: return localized("1:1 Meeting")
        case .pitch: return localized("Presentation Pitch")
        case .clientMeeting: return localized("Client Meeting")
        case .videoScript: return localized("Video Recording")
        case .quickNotes: return localized("Meeting Agenda")
        }
    }

    var iconName: String {
        switch self {
        case .oneOnOne: return "person.2.fill"
        case .pitch: return "bolt.fill"
        case .clientMeeting: return "briefcase.fill"
        case .videoScript: return "video.fill"
        case .quickNotes: return "list.bullet.clipboard.fill"
        }
    }

    var defaultContent: String {
        if Localization.language == .english {
            switch self {
            case .oneOnOne:
                return """
                [1:1 Alignment]
                1. Icebreaker: How was your week and pace?
                2. Key recent deliverables and wins
                3. Technical or workflow blockers
                4. Mutual feedback and priorities for next week
                5. Open questions and needed support
                """
            case .pitch:
                return """
                [Presentation Pitch]
                • Opening (15s): The core challenge impacting our workflow
                • Solution (30s): How we solve it natively and fast
                • Key Differentials (30s): Zero friction, full privacy, peak performance
                • Proven Results (20s): Measured time saved
                • Call to Action (15s): Scheduling pilots and next steps
                """
            case .clientMeeting:
                return """
                [Client Meeting]
                1. Team introductions and welcoming
                2. Joint review of call objectives
                3. Live demo of progress and features
                4. Open Q&A, suggestions, and validation
                5. Clear milestones, owners, and next check-in
                """
            case .videoScript:
                return """
                [Recording Script]
                • Hook (0-5s): Keep perfect eye contact with the camera in any call!
                • Introduction (5-20s): Meet the teleprompter integrated directly into the Notch
                • Demo (20-60s): Smoothly scrolling script right under the FaceTime camera
                • Takeaway (60-80s): No glance-away to secondary screens
                • Wrap-up: Try it today!
                """
            case .quickNotes:
                return """
                [Meeting Agenda]
                - Goal 1: Align on delivery scope
                - Goal 2: Validate rollout schedule
                - Goal 3: Clarify integration questions
                - Quick call notes:
                """
            }
        } else {
            switch self {
            case .oneOnOne:
                return """
                [Alinhamento 1:1]
                1. Quebra-gelo: Como foi a semana e o ritmo de trabalho?
                2. Principais entregas e conquistas recentes
                3. Bloqueios ou impedimentos técnicos/processuais
                4. Feedback mútuo e prioridades da próxima semana
                5. Perguntas finais e suporte necessário
                """
            case .pitch:
                return """
                [Pitch de Apresentação]
                • Abertura (15s): O grande problema que afeta nossa rotina
                • A Solução (30s): Como resolvemos isso de forma nativa e rápida
                • Diferenciais (30s): Zero atrito, privacidade total e máxima performance
                • Casos de Sucesso (20s): Economia de tempo comprovada
                • Call to Action (15s): Agendamento de testes e próximos passos
                """
            case .clientMeeting:
                return """
                [Reunião com Cliente]
                1. Apresentação inicial da equipe e agradecimentos
                2. Revisão conjunta dos objetivos da chamada
                3. Demonstração prática do progresso e funcionalidades
                4. Espaço para dúvidas, sugestões e validações
                5. Definição clara de prazos e responsáveis pelas ações
                """
            case .videoScript:
                return """
                [Roteiro de Gravação]
                • Gancho (0-5s): Mantenha contato visual perfeito com a câmera em qualquer call!
                • Apresentação (5-20s): Conheça o novo Teleprompter integrado ao Notch
                • Demonstração (20-60s): Roteiro rolando suavemente bem embaixo da câmera FaceTime
                • Conclusão (60-80s): Sem desviar o olhar para telas secundárias
                • Encerramento: Teste hoje mesmo!
                """
            case .quickNotes:
                return """
                [Pauta da Reunião]
                - Meta 1: Alinhar o escopo da entrega
                - Meta 2: Validar cronograma de lançamento
                - Meta 3: Tirar dúvidas sobre a integração
                - Anotações rápidas durante a call:
                """
            }
        }
    }
}
