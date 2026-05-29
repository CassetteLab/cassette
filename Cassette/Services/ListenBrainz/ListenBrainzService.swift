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

    // MARK: - Scrobbling Keychain / UserDefaults keys

    private static let scrobblingTokenKeychainKey    = "app.cassette.listenbrainz.token"
    private static let scrobblingUsernameKeychainKey = "app.cassette.listenbrainz.username"
    private static let scrobblingEnabledDefaultsKey  = "app.cassette.listenbrainz.scrobbling.isEnabled"
    private static let scrobblingServerURLDefaultsKey = "app.cassette.listenbrainz.scrobbling.serverRootURL"
    static let defaultScrobblingServerURL = "https://api.listenbrainz.org"

    private let client: ListenBrainzClient
    private let keychain: any KeychainServiceProtocol
    private let userDefaults: UserDefaults

    // MARK: - Recommendations state

    private var isEnabled: Bool
    private var username: String?
    private var validationStatus: ValidationStatus = .unknown

    // MARK: - Scrobbling state

    private var scrobblingEnabled: Bool = false
    private var scrobblingUsername: String?
    private var scrobblingValidationStatus: ValidationStatus = .unknown

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

    /// Loads persisted state for both recommendations and scrobbling.
    /// Call once from AppContainer after init.
    func loadPersistedState() async {
        // Recommendations
        let persistedUsername = try? await keychain.retrieve(String.self, forKey: Self.usernameKeychainKey)
        username = persistedUsername
        Logger.listenBrainz.debug("State loaded — isEnabled=\(self.isEnabled, privacy: .public) hasUsername=\(self.username != nil, privacy: .public)")
        if persistedUsername != nil {
            try? await revalidate()
        }

        // Scrobbling
        scrobblingEnabled = userDefaults.bool(forKey: Self.scrobblingEnabledDefaultsKey)
        scrobblingUsername = try? await keychain.retrieve(String.self, forKey: Self.scrobblingUsernameKeychainKey)
        if scrobblingUsername != nil {
            scrobblingValidationStatus = .valid
        }
        Logger.listenBrainz.debug("Scrobbling state loaded — enabled=\(self.scrobblingEnabled, privacy: .public) hasUsername=\(self.scrobblingUsername != nil, privacy: .public)")
    }

    // MARK: - Recommendations public interface

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

    /// Purges all recommendations state — username, enabled flag, validation status.
    func clearCredentials() async {
        username = nil
        isEnabled = false
        validationStatus = .unknown
        userDefaults.set(false, forKey: Self.isEnabledDefaultsKey)
        try? await keychain.delete(forKey: Self.usernameKeychainKey)
        Logger.listenBrainz.info("ListenBrainz credentials cleared")
    }

    // MARK: - Scrobbling public interface

    func scrobblingSnapshot() -> ScrobblingSnapshot {
        ScrobblingSnapshot(
            isEnabled: scrobblingEnabled,
            username: scrobblingUsername,
            serverRootURL: userDefaults.string(forKey: Self.scrobblingServerURLDefaultsKey) ?? Self.defaultScrobblingServerURL,
            validationStatus: scrobblingValidationStatus
        )
    }

    /// Validates `token` against `rootURL`, persists credentials on success, and enables scrobbling.
    /// Throws `ListenBrainzError.unauthorized` when the server responds with valid:false.
    /// Token is never included in log output or error messages.
    func validateAndSaveScrobblingToken(_ token: String, rootURL: URL) async throws {
        scrobblingValidationStatus = .validating
        let result: ListenBrainzValidation
        do {
            result = try await client.validateToken(token, rootURL: rootURL)
        } catch {
            scrobblingValidationStatus = .invalid(reason: error.localizedDescription)
            throw error
        }
        guard result.isValid else {
            scrobblingValidationStatus = .invalid(reason: "Token is not valid for this server.")
            throw ListenBrainzError.unauthorized
        }
        try await keychain.store(token, forKey: Self.scrobblingTokenKeychainKey)
        if let username = result.username {
            try await keychain.store(username, forKey: Self.scrobblingUsernameKeychainKey)
            scrobblingUsername = username
        }
        let normalizedURL = Self.normalizeServerURL(rootURL.absoluteString)
        userDefaults.set(normalizedURL, forKey: Self.scrobblingServerURLDefaultsKey)
        scrobblingEnabled = true
        userDefaults.set(true, forKey: Self.scrobblingEnabledDefaultsKey)
        scrobblingValidationStatus = .valid
        Logger.listenBrainz.info("Scrobbling token validated and saved")
    }

    /// Re-enables scrobbling without re-validating. No-op if no token has been stored.
    func enableScrobbling() async {
        guard scrobblingUsername != nil else { return }
        scrobblingEnabled = true
        userDefaults.set(true, forKey: Self.scrobblingEnabledDefaultsKey)
        Logger.listenBrainz.info("Scrobbling re-enabled")
    }

    /// Disables scrobbling without removing the stored token — low-friction re-enable.
    func disableScrobbling() async {
        scrobblingEnabled = false
        userDefaults.set(false, forKey: Self.scrobblingEnabledDefaultsKey)
        Logger.listenBrainz.info("Scrobbling disabled")
    }

    /// Purges scrobbling token, username, and all related config.
    func clearScrobblingToken() async {
        scrobblingEnabled = false
        scrobblingUsername = nil
        scrobblingValidationStatus = .unknown
        userDefaults.set(false, forKey: Self.scrobblingEnabledDefaultsKey)
        try? await keychain.delete(forKey: Self.scrobblingTokenKeychainKey)
        try? await keychain.delete(forKey: Self.scrobblingUsernameKeychainKey)
        Logger.listenBrainz.info("Scrobbling credentials cleared")
    }

    /// Trims whitespace and strips trailing slashes for consistent path joining.
    nonisolated static func normalizeServerURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
