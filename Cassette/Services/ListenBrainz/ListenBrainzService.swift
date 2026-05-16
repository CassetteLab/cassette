// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog

actor ListenBrainzService {
    // Reuses the shared KeychainService actor (service group = "app.cassette.server-credentials").
    // The key "listenbrainz-username" is namespaced to prevent collision with server credentials.
    private static let usernameKeychainKey = "listenbrainz-username"
    private static let isEnabledDefaultsKey = "app.cassette.listenbrainz.isEnabled"

    private let client: ListenBrainzClient
    private let keychain: any KeychainServiceProtocol
    private let userDefaults: UserDefaults

    private var isEnabled: Bool
    private var username: String?
    private var validationStatus: ValidationStatus = .unknown

    init(
        client: ListenBrainzClient,
        keychain: any KeychainServiceProtocol,
        userDefaults: UserDefaults = .standard
    ) {
        self.client = client
        self.keychain = keychain
        self.userDefaults = userDefaults
        self.isEnabled = userDefaults.bool(forKey: Self.isEnabledDefaultsKey)
    }

    /// Loads persisted username from Keychain. Call once from AppContainer after init.
    /// No network calls are made.
    func loadPersistedState() async {
        username = try? await keychain.retrieve(String.self, forKey: Self.usernameKeychainKey)
        Logger.listenBrainz.debug("State loaded — isEnabled=\(self.isEnabled, privacy: .public) hasUsername=\(self.username != nil, privacy: .public)")
    }

    // MARK: - Public interface

    func currentSnapshot() -> ListenBrainzSnapshot {
        ListenBrainzSnapshot(isEnabled: isEnabled, username: username, validationStatus: validationStatus)
    }

    /// Validates the username against ListenBrainz. On success, persists and flips isEnabled.
    func enable(username: String) async throws {
        validationStatus = .validating
        do {
            _ = try await client.validateUsername(username)
        } catch {
            validationStatus = .invalid(reason: error.localizedDescription)
            throw error
        }
        self.username = username
        try await keychain.store(username, forKey: Self.usernameKeychainKey)
        isEnabled = true
        userDefaults.set(true, forKey: Self.isEnabledDefaultsKey)
        validationStatus = .valid
        Logger.listenBrainz.info("ListenBrainz enabled")
    }

    /// Disables integration. Username is intentionally kept in Keychain so re-enabling
    /// requires no re-entry — minimal friction for temporary disconnection.
    func disable() async {
        isEnabled = false
        userDefaults.set(false, forKey: Self.isEnabledDefaultsKey)
        Logger.listenBrainz.info("ListenBrainz disabled")
    }

    /// Re-runs username validation if a username is stored. No-op if no username is persisted.
    func revalidate() async throws {
        guard let existing = username else {
            Logger.listenBrainz.debug("revalidate: no username stored, skipping")
            return
        }
        validationStatus = .validating
        do {
            _ = try await client.validateUsername(existing)
            validationStatus = .valid
            Logger.listenBrainz.info("revalidate succeeded")
        } catch {
            validationStatus = .invalid(reason: error.localizedDescription)
            throw error
        }
    }

    /// Purges all state — username, enabled flag, validation status.
    func clearCredentials() async {
        username = nil
        isEnabled = false
        validationStatus = .unknown
        userDefaults.set(false, forKey: Self.isEnabledDefaultsKey)
        try? await keychain.delete(forKey: Self.usernameKeychainKey)
        Logger.listenBrainz.info("ListenBrainz credentials cleared")
    }
}
