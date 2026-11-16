import Foundation
import Testing
@testable import MonoHub

@Suite("Claude Context Tests")
struct ClaudeContextTests {
    @Test("Context token formatting for sub-million tokens")
    func testTokenFormattingSubMillion() {
        let session = ClaudeContextSession(
            sessionId: "test-session-1",
            projectName: "MonoAiBar",
            modelName: "Sonnet",
            activeInputTokens: 50_000,
            cacheCreationTokens: 10_000,
            cacheReadTokens: 5_000,
            totalContextTokens: 65_000,
            contextLimit: 200_000,
            contextPercent: 32.5,
            lastPrompt: "Hello",
            modifiedAt: Date()
        )

        #expect(session.formattedTokens == "65k / 200k")
        #expect(session.contextPercent == 32.5)
    }

    @Test("Context token formatting for million+ tokens")
    func testTokenFormattingMillion() {
        let session = ClaudeContextSession(
            sessionId: "test-session-2",
            projectName: "MonoAiBar",
            modelName: "Sonnet",
            activeInputTokens: 400_000,
            cacheCreationTokens: 50_000,
            cacheReadTokens: 10_000,
            totalContextTokens: 460_000,
            contextLimit: 1_000_000,
            contextPercent: 46.0,
            lastPrompt: "Refactor",
            modifiedAt: Date()
        )

        #expect(session.formattedTokens == "460k / 1M")
    }

    @Test("Context limit detection for 1M Claude 4.6/4.8/5.5 models vs 200k legacy")
    func testContextLimits() {
        #expect(ClaudeContextService.contextLimit(forModel: "claude-opus-5-5-20261001", totalTokens: 80_000) == 1_000_000)
        #expect(ClaudeContextService.contextLimit(forModel: "claude-sonnet-5-5", totalTokens: 45_000) == 1_000_000)
        #expect(ClaudeContextService.contextLimit(forModel: "claude-opus-4-8", totalTokens: 159_000) == 1_000_000)
        #expect(ClaudeContextService.contextLimit(forModel: "claude-sonnet-4-6", totalTokens: 120_000) == 1_000_000)
        #expect(ClaudeContextService.contextLimit(forModel: "claude-3-7-sonnet", totalTokens: 50_000) == 200_000)
        #expect(ClaudeContextService.contextLimit(forModel: "claude-haiku-4-5", totalTokens: 50_000) == 200_000)
    }

    @Test("Friendly model name preserves major.minor version")
    func testFriendlyModelName() {
        #expect(ClaudeContextService.friendlyModelName("claude-opus-5-5-20261001") == "Opus 5.5")
        #expect(ClaudeContextService.friendlyModelName("claude-sonnet-4-6") == "Sonnet 4.6")
        #expect(ClaudeContextService.friendlyModelName("claude-3-7-sonnet-latest") == "Sonnet 3.7")
        #expect(ClaudeContextService.friendlyModelName("claude-haiku-4-5") == "Haiku 4.5")
    }

    @Test("Clean project name preserves hyphenated repository slugs")
    func testCleanProjectName() {
        #expect(
            ClaudeContextService.cleanProjectName(
                "-Users-alice-dev-work-pims-mobile-audio-fix",
                homePath: "/Users/alice"
            ) == "pims-mobile-audio-fix"
        )
        #expect(
            ClaudeContextService.cleanProjectName(
                "-Users-alice-dev-MonoHub",
                homePath: "/Users/alice"
            ) == "MonoHub"
        )
    }

    @Test("Parse session handles multi-byte UTF-8 boundary and includes output_tokens")
    func testParseSessionMultiByteAndOutputTokens() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let line1 = #"{"type":"last-prompt","lastPrompt":"Otimizar monitoramento do Claude 🚀"}"#
        let line2 = #"{"type":"assistant","message":{"model":"claude-opus-4-8","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":2000,"cache_read_input_tokens":96500}}}"#
        let payload = line1 + "\n" + line2 + "\n"
        try payload.write(to: tempURL, atomically: true, encoding: .utf8)

        let session = ClaudeContextService.parseSession(
            fileURL: tempURL,
            modified: Date(),
            projectName: "MonoHub"
        )
        #expect(session != nil)
        #expect(session?.totalContextTokens == 100_000)
        #expect(session?.contextLimit == 1_000_000)
        #expect(session?.contextPercent == 10.0)
        #expect(session?.modelName == "Opus 4.8")
        #expect(session?.lastPrompt == "Otimizar monitoramento do Claude 🚀")
    }
}
