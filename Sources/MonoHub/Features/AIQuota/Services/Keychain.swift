import CryptoKit
import Foundation
import IOKit
import OSLog

nonisolated enum Keychain {
    struct Item: Sendable {
        let secret: String
        let account: String?
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cachedStore: [String: [String: String]]?

    private static var vaultURL: URL {
        if AppInfo.isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("monohub-test-vault-\(ProcessInfo.processInfo.processIdentifier).vault")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("MonoHub", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return dir.appendingPathComponent("credentials.vault")
    }

    private static var encryptionKey: SymmetricKey {
        let uuid = hardwareUUID() ?? "monohub-local-device"
        let material = "com.antigravity.monohub.vault.v1|\(uuid)|\(NSUserName())"
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: digest)
    }

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cfProp = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }
        return cfProp
    }

    private static func loadLocked() -> [String: [String: String]] {
        if let cachedStore {
            return cachedStore
        }
        let url = vaultURL
        guard let combined = try? Data(contentsOf: url),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(box, using: encryptionKey),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: plaintext) else {
            cachedStore = [:]
            return [:]
        }
        cachedStore = decoded
        return decoded
    }

    @discardableResult
    private static func saveLocked(_ store: [String: [String: String]]) -> Bool {
        cachedStore = store
        let url = vaultURL
        guard let plaintext = try? JSONEncoder().encode(store),
              let sealed = try? AES.GCM.seal(plaintext, using: encryptionKey),
              let combined = sealed.combined else {
            return false
        }
        do {
            try combined.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            Log.credentials.error("vault write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func read(service: String, account: String? = nil) -> Item? {
        lock.lock()
        defer { lock.unlock() }
        let store = loadLocked()
        guard let accounts = store[service], !accounts.isEmpty else { return nil }
        if let account {
            if let secret = accounts[account]?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty {
                return Item(secret: secret, account: account)
            }

        }
        guard let (resolvedAccount, rawSecret) = accounts.first else { return nil }
        let secret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return nil }
        return Item(secret: secret, account: resolvedAccount)
    }

    static func exists(service: String) -> Bool {
        read(service: service) != nil
    }

    @discardableResult
    static func write(service: String, account: String, secret: String) -> Bool {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return delete(service: service, account: account)
        }
        lock.lock()
        defer { lock.unlock() }
        var store = loadLocked()
        var serviceAccounts = store[service] ?? [:]
        serviceAccounts[account] = trimmed
        store[service] = serviceAccounts
        return saveLocked(store)
    }

    @discardableResult
    static func delete(service: String, account: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var store = loadLocked()
        if let account {
            store[service]?.removeValue(forKey: account)
            if store[service]?.isEmpty == true {
                store.removeValue(forKey: service)
            }
        } else {
            store.removeValue(forKey: service)
        }
        return saveLocked(store)
    }
}
