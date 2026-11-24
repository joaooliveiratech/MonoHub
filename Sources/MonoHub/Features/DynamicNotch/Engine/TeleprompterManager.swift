import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
final class TeleprompterManager {
    static let shared = TeleprompterManager()

    var scripts: [TeleprompterScript] = []
    var activeScriptID: UUID = UUID()
    var mode: TeleprompterMode = .reading
    var isPlaying: Bool = false
    var isPinned: Bool = false

    var scrollOffset: CGFloat = 0
    var maxScrollOffset: CGFloat = 0
    var speed: Double {
        didSet { NotchPreferences.shared.teleprompterSpeed = speed }
    }
    var fontSize: Double {
        didSet { NotchPreferences.shared.teleprompterFontSize = fontSize }
    }
    var showFocusGuide: Bool {
        didSet { NotchPreferences.shared.teleprompterShowFocusGuide = showFocusGuide }
    }
    var isMirrored: Bool {
        didSet { NotchPreferences.shared.teleprompterIsMirrored = isMirrored }
    }
    var isCameraEnabled: Bool {
        didSet { defaults.set(isCameraEnabled, forKey: "monohub.teleprompter.isCameraEnabled") }
    }
    var cameraDimming: Double {
        didSet { defaults.set(cameraDimming, forKey: "monohub.teleprompter.cameraDimming") }
    }
    var elapsedTime: TimeInterval = 0

    @ObservationIgnored private var rawElapsedTime: TimeInterval = 0
    @ObservationIgnored private var scrollTask: Task<Void, Never>?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let scriptsKey = "monohub.teleprompter.scripts"
    @ObservationIgnored private static let activeIdKey = "monohub.teleprompter.activeScriptId"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let prefs = NotchPreferences.shared
        self.speed = prefs.teleprompterSpeed
        self.fontSize = prefs.teleprompterFontSize
        self.showFocusGuide = prefs.teleprompterShowFocusGuide
        self.isMirrored = prefs.teleprompterIsMirrored
        self.isCameraEnabled = defaults.object(forKey: "monohub.teleprompter.isCameraEnabled") == nil ? true : defaults.bool(forKey: "monohub.teleprompter.isCameraEnabled")
        self.cameraDimming = defaults.object(forKey: "monohub.teleprompter.cameraDimming") == nil ? 0.45 : defaults.double(forKey: "monohub.teleprompter.cameraDimming")
        loadPersistedState()
    }

    var activeScript: TeleprompterScript {
        get {
            scripts.first(where: { $0.id == activeScriptID }) ?? scripts.first ?? TeleprompterScript(title: localized("Quick Notes"))
        }
        set {
            if let index = scripts.firstIndex(where: { $0.id == newValue.id }) {
                scripts[index] = newValue
            } else {
                scripts.append(newValue)
            }
            activeScriptID = newValue.id
            persistScripts()
        }
    }

    var scrollProgress: Double {
        guard maxScrollOffset > 0 else { return 0 }
        return min(1.0, max(0.0, Double(scrollOffset / maxScrollOffset)))
    }

    var formattedElapsedTime: String {
        let total = Int(elapsedTime)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !isPlaying else { return }

        if maxScrollOffset > 0 && scrollOffset >= maxScrollOffset - 4 {
            scrollOffset = 0
            rawElapsedTime = 0
            elapsedTime = 0
        }
        isPlaying = true

        scrollTask?.cancel()
        scrollTask = Task { @MainActor [weak self] in
            var lastTick = Date()
            while !Task.isCancelled {
                let frameDuration: Duration = ProcessInfo.processInfo.isLowPowerModeEnabled
                    ? .milliseconds(33)
                    : .nanoseconds(16_666_667)
                try? await Task.sleep(for: frameDuration, tolerance: .milliseconds(2))
                guard let self, self.isPlaying, !Task.isCancelled else { break }
                if NotchWindowController.shared.isDisplayAsleep {
                    self.pause()
                    break
                }
                let now = Date()
                let dt = min(0.05, now.timeIntervalSince(lastTick))
                lastTick = now
                self.advanceScroll(dt: dt)
            }
        }
    }

    func pause() {
        isPlaying = false
        scrollTask?.cancel()
        scrollTask = nil
    }

    func rewind() {
        pause()
        scrollOffset = 0
        rawElapsedTime = 0
        elapsedTime = 0
    }

    private func advanceScroll(dt: TimeInterval) {
        let delta = CGFloat(speed * dt)
        rawElapsedTime += dt
        if Int(rawElapsedTime) != Int(elapsedTime) {
            elapsedTime = floor(rawElapsedTime)
        }

        if maxScrollOffset > 0 {
            scrollOffset = min(maxScrollOffset, scrollOffset + delta)
            if scrollOffset >= maxScrollOffset {
                pause()
            }
        } else {
            scrollOffset += delta
        }
    }

    func scrubTo(offset: CGFloat) {
        let limit = max(0, maxScrollOffset)
        scrollOffset = max(0, min(limit, offset))
    }

    func adjustSpeed(by delta: Double) {
        speed = min(120.0, max(10.0, speed + delta))
    }

    func adjustFontSize(by delta: Double) {
        fontSize = min(28.0, max(12.0, fontSize + delta))
    }

    func selectScript(id: UUID) {
        guard id != activeScriptID, scripts.contains(where: { $0.id == id }) else { return }
        rewind()
        activeScriptID = id
        defaults.set(id.uuidString, forKey: Self.activeIdKey)
    }

    func createNewScript(title: String = "Novo Roteiro", content: String = "") {
        rewind()
        let newScript = TeleprompterScript(title: title, content: content)
        scripts.insert(newScript, at: 0)
        activeScriptID = newScript.id
        mode = .editing
        persistScripts()
    }

    func duplicateActiveScript() {
        let current = activeScript
        let duplicate = TeleprompterScript(
            title: localized("%@ (Copy)", current.title),
            content: current.content
        )
        scripts.insert(duplicate, at: 0)
        activeScriptID = duplicate.id
        persistScripts()
    }

    func updateActiveContent(_ newContent: String) {
        var current = activeScript
        current.content = newContent
        current.updatedAt = Date()
        if let index = scripts.firstIndex(where: { $0.id == current.id }) {
            scripts[index] = current
        } else {
            scripts.append(current)
        }
        activeScriptID = current.id
        scheduleDebouncedPersist()
    }

    func updateActiveTitle(_ newTitle: String) {
        var current = activeScript
        current.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localized("Untitled") : newTitle
        current.updatedAt = Date()
        if let index = scripts.firstIndex(where: { $0.id == current.id }) {
            scripts[index] = current
        } else {
            scripts.append(current)
        }
        activeScriptID = current.id
        scheduleDebouncedPersist()
    }

    func deleteScript(id: UUID) {
        guard scripts.count > 1 else {

            if var first = scripts.first {
                first.title = localized("Quick Notes")
                first.content = ""
                first.updatedAt = Date()
                scripts = [first]
                activeScriptID = first.id
                rewind()
                persistScripts()
            }
            return
        }

        scripts.removeAll { $0.id == id }
        if activeScriptID == id, let first = scripts.first {
            activeScriptID = first.id
            defaults.set(first.id.uuidString, forKey: Self.activeIdKey)
        }
        rewind()
        persistScripts()
    }

    func applyTemplate(_ template: TeleprompterTemplate) {
        rewind()
        var current = activeScript
        if current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current.title = template.title
            current.content = template.defaultContent
        } else {

            let newScript = TeleprompterScript(
                title: template.title,
                content: template.defaultContent
            )
            scripts.insert(newScript, at: 0)
            activeScriptID = newScript.id
            persistScripts()
            return
        }
        current.updatedAt = Date()
        activeScript = current
    }

    private func scheduleDebouncedPersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.persistScripts()
        }
    }

    private func persistScripts() {
        persistTask?.cancel()
        persistTask = nil
        if let data = try? JSONEncoder().encode(scripts) {
            defaults.set(data, forKey: Self.scriptsKey)
        }
        defaults.set(activeScriptID.uuidString, forKey: Self.activeIdKey)
    }

    private func loadPersistedState() {
        if let data = defaults.data(forKey: Self.scriptsKey),
           let decoded = try? JSONDecoder().decode([TeleprompterScript].self, from: data),
           !decoded.isEmpty {
            self.scripts = decoded
            if let savedIDString = defaults.string(forKey: Self.activeIdKey),
               let savedID = UUID(uuidString: savedIDString),
               decoded.contains(where: { $0.id == savedID }) {
                self.activeScriptID = savedID
            } else {
                self.activeScriptID = decoded.first?.id ?? UUID()
            }
        } else {

            let starterContent = Localization.language == .english
                ? """
                Welcome to MonoHub Teleprompter!

                This scratchpad and teleprompter is positioned right below your Mac's FaceTime camera.

                When reading your talking points or script during calls on Google Meet, Zoom, or Teams, you maintain continuous, natural eye contact with the camera lens.

                Key features:
                • Smooth auto-scrolling with adjustable speed (+ and - buttons).
                • Visual eye-line guide: shows exact camera eye-level.
                • Notes Mode: quickly type or paste your meeting notes.
                • Pin Notch (pin icon): keeps the notch open during your entire call.
                • Shortcuts: press Spacebar to pause or resume scrolling.
                """
                : """
                Bem-vindo ao Teleprompter do MonoHub!

                Este bloco de notas e teleprompter fica posicionado exatamente abaixo da câmera FaceTime do seu Mac.

                Ao ler seus tópicos ou roteiro durante reuniões no Google Meet, Zoom ou Teams, você mantém contato visual contínuo e natural com a lente da câmera.

                Recursos principais:
                • Rolagem automática suave com velocidade regulável (botões + e -).
                • Linha de foco visual: indica a altura exata do olhar na câmera.
                • Modo Anotações: digite ou cole suas notas rapidamente.
                • Fixar Notch (ícone de alfinete): mantém o entalhe aberto durante toda a call.
                • Atalhos: use a barra de Espaço para pausar/retomar a rolagem.
                """
            let starter = TeleprompterScript(
                title: localized("Welcome Script"),
                content: starterContent
            )
            self.scripts = [starter]
            self.activeScriptID = starter.id
            persistScripts()
        }
    }
}
