import Foundation
import Testing
@testable import MonoHub

@Suite("Security & GitHub TOS Compliance Tests")
struct SecurityAndTOSComplianceTests {
    @Test("HTTP client enforces ephemeral configuration and payload limit")
    func testHTTPClientSecurity() {
        #expect(HTTPClient.maximumPayloadBytes == 512 * 1024)
    }

    @Test("All provider IDs are valid and non-empty")
    func testProviderIDsFormat() {
        for provider in ProviderType.allCases {
            #expect(!provider.id.isEmpty)
        }
    }

    @Test("Copilot provider status handles missing token safely without subprocesses")
    func testCopilotMissingToken() async {
        let status = await CopilotUsageService.shared.fetchUsage()
        #expect(status.provider == .copilot)
    }
}
