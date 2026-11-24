import Foundation

nonisolated enum AppInfo {
    static let name = "MonoHub"
    static let appName = "MonoHub"
    static let version = "0.17.7"
    static let build = "63"
    static var userAgent: String { "\(name)/\(version)" }
    static let bundleId = "com.antigravity.monohub"
    static let bundleIdentifier = "com.antigravity.monohub"
    static var fullVersionString: String {
        "\(version) (\(build))"
    }
    static let githubUrl = "https://github.com/joaooliveiratech/MonoHub"
    static let copyright = "Copyright © 2026 Antigravity. All rights reserved."
    static let privacyStatement = "Privado. Zero telemetria. Rede apenas no módulo Cotas de IA, para os provedores ativados."

    static var isRunningTests: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
           ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
           ProcessInfo.processInfo.environment["SWIFT_TESTING"] != nil ||
           ProcessInfo.processInfo.arguments.contains(where: { $0.contains("xctest") || $0.contains("Testing") || $0.contains("test") }) ||
           Bundle.main.bundlePath.hasSuffix(".xctest") ||
           NSClassFromString("XCTestCase") != nil {
            return true
        }
        return false
    }
}
