import Foundation
import AppKit
import CoreGraphics
import Carbon.HIToolbox
import Observation
import Synchronization

@Observable
@MainActor
final class SnippetManager {
    static let shared = SnippetManager()

    private(set) var snippets: [SnippetItem] = [] {
        didSet {
            cachedSnippets.withLock { $0 = snippets.filter { $0.isEnabled && !$0.keyword.isEmpty } }
        }
    }
    var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            updateTapState()
        }
    }

    @ObservationIgnored private var isFeatureActive = false
    @ObservationIgnored private var typingBuffer: String = ""
    @ObservationIgnored private let tapBuffer = Mutex<String>("")
    @ObservationIgnored private let cachedSnippets = Mutex<[SnippetItem]>([])
    @ObservationIgnored private var eventTap: BackgroundEventTap?
    @ObservationIgnored private let maxBufferLength = 32

    private static let storageFileName = "snippets.json"
    private static let enabledDefaultsKey = "MonoHub_Snippets_Enabled"

    init() {
        if UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        }
        loadSnippets()
    }

    func start() {
        isFeatureActive = true
        loadSnippets()
        updateTapState()
    }

    func stop() {
        isFeatureActive = false
        clearBuffer()
        stopEventTap()
    }

    private func updateTapState() {
        guard !AppInfo.isRunningTests else { return }
        let hasExpandableSnippet = snippets.contains { $0.isEnabled && !$0.keyword.isEmpty }
        if isFeatureActive && isEnabled && hasExpandableSnippet && PermissionsManager.shared.hasAccessibility {
            startEventTap()
        } else {
            stopEventTap()
        }
    }

    func addSnippet(_ snippet: SnippetItem) {
        snippets.append(snippet)
        saveSnippets()
    }

    func updateSnippet(_ snippet: SnippetItem) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
            saveSnippets()
        }
    }

    func removeSnippet(id: UUID) {
        snippets.removeAll(where: { $0.id == id })
        saveSnippets()
    }

    func toggleSnippet(id: UUID) {
        if let idx = snippets.firstIndex(where: { $0.id == id }) {
            snippets[idx].isEnabled.toggle()
            saveSnippets()
        }
    }

    func resetToDefaults() {
        snippets = Self.defaultSnippets
        saveSnippets()
    }

    func processCharacter(_ char: Character) {
        typingBuffer.append(char)
        if typingBuffer.count > maxBufferLength {
            typingBuffer.removeFirst(typingBuffer.count - maxBufferLength)
        }
        checkMatch()
    }

    func handleBackspace() {
        if !typingBuffer.isEmpty {
            typingBuffer.removeLast()
        }
    }

    func clearBuffer() {
        typingBuffer.removeAll()
        tapBuffer.withLock { $0.removeAll() }
    }

    @discardableResult
    func checkMatch() -> SnippetItem? {
        guard isEnabled else { return nil }

        for snippet in snippets where snippet.isEnabled {
            let key = snippet.keyword
            guard !key.isEmpty, typingBuffer.hasSuffix(key) else { continue }

            clearBuffer()
            expandSnippet(snippet)
            return snippet
        }
        return nil
    }

    private func expandSnippet(_ snippet: SnippetItem) {
        let expanded = snippet.evaluatedContent()
        let count = snippet.keyword.count

        guard !AppInfo.isRunningTests else { return }

        DispatchQueue.main.async { [weak self] in
            self?.executeReplacement(backspaceCount: count, replacementText: expanded)
        }
    }

    private func executeReplacement(backspaceCount: Int, replacementText: String) {
        let pb = NSPasteboard.general
        let previousString = pb.string(forType: .string)

        for _ in 0..<backspaceCount {
            Self.postVirtualKey(UInt16(kVK_Delete), flags: [])
        }

        pb.clearContents()
        let transientType = NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType")
        pb.setData(Data(), forType: transientType)
        pb.setString(replacementText, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
            Self.postVirtualKey(UInt16(kVK_ANSI_V), flags: .maskCommand)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let previousString, pb.string(forType: .string) == replacementText {
                    pb.clearContents()
                    pb.setData(Data(), forType: transientType)
                    pb.setString(previousString, forType: .string)
                }
            }
        }
    }

    private static func postVirtualKey(_ key: UInt16, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    private func startEventTap() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.keyDown.rawValue)
        let tap = BackgroundEventTap(
            mask: CGEventMask(mask),
            options: .listenOnly,
            callback: snippetEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        tap?.start(name: "com.antigravity.monohub.snippets.tap")
        self.eventTap = tap
    }

    func reenableTap() {
        eventTap?.reenable()
    }

    private func stopEventTap() {
        eventTap?.invalidate()
        eventTap = nil
    }

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MonoHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.storageFileName)
    }

    private func loadSnippets() {
        let url = storageURL
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([SnippetItem].self, from: data) {
            self.snippets = decoded
        } else {
            self.snippets = Self.defaultSnippets
            saveSnippets()
        }
    }

    private func saveSnippets() {
        let url = storageURL
        if let data = try? JSONEncoder().encode(snippets) {
            try? data.write(to: url, options: .atomic)
        }
        updateTapState()
    }

    static let defaultSnippets: [SnippetItem] = [
        SnippetItem(keyword: "!shrug", content: "¯\\_(ツ)_/¯", label: "Emoji Shrug"),
        SnippetItem(keyword: "!lenny", content: "( ͡° ͜ʖ ͡°)", label: "Lenny Face"),
        SnippetItem(keyword: "!data", content: "{date}", label: "Data de Hoje"),
        SnippetItem(keyword: "!hora", content: "{time}", label: "Hora Atual"),
        SnippetItem(keyword: "!email", content: "contato@exemplo.com", label: "E-mail de Contato"),
        SnippetItem(keyword: "!pix", content: "chave-pix-exemplo", label: "Chave Pix"),
        SnippetItem(keyword: "!cnpj", content: "00.000.000/0001-00", label: "CNPJ Padrão"),
        SnippetItem(keyword: "!mono", content: "MonoHub para macOS", label: "Assinatura MonoHub")
    ]

    nonisolated func handleTapBackspace() {
        tapBuffer.withLock {
            if !$0.isEmpty { $0.removeLast() }
        }
    }

    nonisolated func handleTapClear() {
        tapBuffer.withLock {
            $0.removeAll()
        }
    }

    nonisolated func handleTapCharacter(_ char: Character) {
        let matched: SnippetItem? = tapBuffer.withLock { buf in
            buf.append(char)
            if buf.count > maxBufferLength {
                buf.removeFirst(buf.count - maxBufferLength)
            }
            let active = cachedSnippets.withLock { $0 }
            for snippet in active {
                if buf.hasSuffix(snippet.keyword) {
                    buf.removeAll()
                    return snippet
                }
            }
            return nil
        }

        if let matched {
            Task { @MainActor in
                self.expandSnippet(matched)
            }
        }
    }
}

nonisolated private func snippetEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout, let userInfo {
        let manager = Unmanaged<SnippetManager>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor in
            manager.reenableTap()
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown, let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<SnippetManager>.fromOpaque(userInfo).takeUnretainedValue()
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)

    if keycode == Int64(kVK_Delete) {
        manager.handleTapBackspace()
        return Unmanaged.passUnretained(event)
    }

    if keycode == Int64(kVK_Return) || keycode == Int64(kVK_Tab) || keycode == Int64(kVK_Escape) {
        manager.handleTapClear()
        return Unmanaged.passUnretained(event)
    }

    var length = 0
    event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
    if length > 0 {
        var chars = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &chars)
        let str = String(utf16CodeUnits: chars, count: length)
        if let char = str.first, !char.isNewline {
            manager.handleTapCharacter(char)
        }
    }

    return Unmanaged.passUnretained(event)
}
