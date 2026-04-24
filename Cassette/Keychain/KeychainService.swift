// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import Security
import OSLog

actor KeychainService: KeychainServiceProtocol {
    // kSecAttrService groups all Cassette credentials for bulk queries and cleanup.
    private let service = "app.cassette.server-credentials"

    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        let data = try JSONEncoder().encode(value)

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String:   data
        ]

        // Delete any existing item first (update via delete+add is simpler than SecItemUpdate).
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            // Never log `data` — it may contain credentials.
            Logger.keychain.error("Keychain write failed for key '\(key, privacy: .public)' — OSStatus \(status)")
            throw CassetteError.keychainWriteFailed(status)
        }
    }

    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            Logger.keychain.error("Keychain read failed for key '\(key, privacy: .public)' — OSStatus \(status)")
            throw CassetteError.keychainReadFailed(status)
        }

        guard let data = result as? Data else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func delete(forKey key: String) async throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Logger.keychain.error("Keychain delete failed for key '\(key, privacy: .public)' — OSStatus \(status)")
            throw CassetteError.keychainDeleteFailed(status)
        }
    }
}
