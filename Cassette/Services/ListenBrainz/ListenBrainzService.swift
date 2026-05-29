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
    /// True when a token is present in the Keychain. Set in loadPersistedState and on token store/clear.
    /// Avoids a Keychain round-trip for every track change when scrobbling is not configured.
    private var hasScrobblingToken: Bool = false

    // MARK: - Offline queue

    private let queueFileURL: URL
    private var pendingQueue: [PendingListen] = []
    /// Guards against two concurrent flushes re-POSTing the same batch.
    /// Set synchronously before the first await in flushOfflineQueue; reset via defer.
    private var isFlushing: Bool = false

    /// Number of listens waiting for a successful flush. Exposed for diagnostics and tests.
    var pendingListenCount: Int { pendingQueue.count }

    init(
        client: ListenBrainzClient,
        keychain: any KeychainServiceProtocol,
        userDefaults: UserDefaults = .standard,
        queueFileURL: URL? = nil
    ) {
        self.client = client
        self.keychain = keychain
        self.userDefaults = userDefaults
        self.isEnabled = userDefaults.bool(forKey: Self.isEnabledDefaultsKey)
        self.queueFileURL = queueFileURL ?? Self.makeDefaultQueueFileURL()
    }

    /// Resolves the default queue file path in Application Support, creating the subdirectory if needed.
    /// Falls back to the temporary directory on unexpected filesystem errors.
    private static func makeDefaultQueueFileURL() -> URL {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("app.cassette", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("listenbrainz-queue.json")
        } catch {
            Logger.listenBrainz.error("Failed to resolve Application Support path: \(error, privacy: .public)")
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("app.cassette.listenbrainz-queue.json")
        }
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
        let storedToken = try? await keychain.retrieve(String.self, forKey: Self.scrobblingTokenKeychainKey)
        hasScrobblingToken = storedToken != nil
        Logger.listenBrainz.debug("Scrobbling state loaded — enabled=\(self.scrobblingEnabled, privacy: .public) hasToken=\(self.hasScrobblingToken, privacy: .public)")

        // Offline queue — load persisted listens then attempt an immediate flush
        loadQueue()
        await flushOfflineQueue()
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
        hasScrobblingToken = true
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

    /// Purges scrobbling token, username, all related config, and the offline queue.
    /// The queue belongs to the removed account — it must never flush to a different future account.
    func clearScrobblingToken() async {
        scrobblingEnabled = false
        scrobblingUsername = nil
        scrobblingValidationStatus = .unknown
        hasScrobblingToken = false
        pendingQueue = []
        try? FileManager.default.removeItem(at: queueFileURL)
        userDefaults.set(false, forKey: Self.scrobblingEnabledDefaultsKey)
        try? await keychain.delete(forKey: Self.scrobblingTokenKeychainKey)
        try? await keychain.delete(forKey: Self.scrobblingUsernameKeychainKey)
        Logger.listenBrainz.info("Scrobbling credentials cleared")
    }

    // MARK: - Scrobbling notifications (called by PlayerService)

    /// Submits a playing_now notification to ListenBrainz. No-op when scrobbling is disabled or
    /// no token is stored. The 3-second delay and still-playing guard are applied by the caller.
    /// playing_now failures are NEVER queued — they are ephemeral and stale by flush time.
    func notifyTrackStarted(song: DisplayableSong) async {
        guard scrobblingEnabled, hasScrobblingToken else { return }
        guard let token = try? await keychain.retrieve(String.self, forKey: Self.scrobblingTokenKeychainKey) else { return }
        let rootURLString = userDefaults.string(forKey: Self.scrobblingServerURLDefaultsKey) ?? Self.defaultScrobblingServerURL
        guard let rootURL = URL(string: rootURLString) else { return }
        do {
            try await client.submitPlayingNow(track: LBTrackMetadata(from: song), rootURL: rootURL, token: token)
            Logger.listenBrainz.debug("playing_now submitted")
        } catch {
            Logger.listenBrainz.debug("playing_now failed: \(error, privacy: .public)")
        }
    }

    /// Submits a single completed listen to ListenBrainz. On transient failure the listen is
    /// persisted to the offline queue. On permanent failure (auth/4xx) it is dropped.
    func notifyScrobbleThreshold(song: DisplayableSong, startDate: Date) async {
        guard scrobblingEnabled, hasScrobblingToken else { return }
        guard let token = try? await keychain.retrieve(String.self, forKey: Self.scrobblingTokenKeychainKey) else { return }
        let rootURLString = userDefaults.string(forKey: Self.scrobblingServerURLDefaultsKey) ?? Self.defaultScrobblingServerURL
        guard let rootURL = URL(string: rootURLString) else { return }
        let listenedAt = Int(startDate.timeIntervalSince1970)
        let meta = LBTrackMetadata(from: song)
        do {
            try await client.submitListen(track: meta, listenedAt: listenedAt, rootURL: rootURL, token: token)
            Logger.listenBrainz.debug("single listen submitted")
            await flushOfflineQueue()
        } catch {
            let isTransient = (error as? ListenBrainzError)?.isTransient ?? true
            if isTransient {
                enqueue(PendingListen(
                    listenedAt: listenedAt,
                    trackName: meta.trackName,
                    artistName: meta.artistName,
                    releaseName: meta.releaseName,
                    durationMs: meta.durationMs
                ))
                Logger.listenBrainz.debug("single listen queued after transient error")
            } else {
                Logger.listenBrainz.debug("single listen dropped (permanent error)")
            }
        }
    }

    // MARK: - Offline queue — flush

    /// Attempts to POST all pending listens as a single "import" batch.
    /// Triggers: reconnect (CassetteApp .task), app launch (loadPersistedState),
    /// after any successful live single submit (free online signal).
    ///
    /// Re-entrancy: isFlushing is set synchronously before the first await, preventing
    /// two concurrent callers from both building and posting the same batch. On confirmed
    /// 200 only the submitted batch is dropped; listens enqueued during the POST are kept.
    func flushOfflineQueue() async {
        guard !pendingQueue.isEmpty else { return }
        guard scrobblingEnabled, hasScrobblingToken else { return }
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        guard let token = try? await keychain.retrieve(String.self, forKey: Self.scrobblingTokenKeychainKey) else { return }
        let rootURLString = userDefaults.string(forKey: Self.scrobblingServerURLDefaultsKey) ?? Self.defaultScrobblingServerURL
        guard let rootURL = URL(string: rootURLString) else { return }

        let batch = pendingQueue
        let listens = batch.map { listen in
            (
                listenedAt: listen.listenedAt,
                track: LBTrackMetadata(
                    trackName: listen.trackName,
                    artistName: listen.artistName,
                    releaseName: listen.releaseName,
                    durationMs: listen.durationMs
                )
            )
        }

        do {
            try await client.submitImport(listens: listens, rootURL: rootURL, token: token)
            // dropFirst is safe if clearScrobblingToken() raced and emptied the queue.
            pendingQueue = Array(pendingQueue.dropFirst(batch.count))
            saveQueue()
            Logger.listenBrainz.info("Offline queue flushed: \(batch.count, privacy: .public) listens")
        } catch {
            Logger.listenBrainz.debug("Offline queue flush failed, will retry: \(error, privacy: .public)")
        }
    }

    // MARK: - Offline queue — persistence helpers

    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queueFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: queueFileURL)
            pendingQueue = try JSONDecoder().decode([PendingListen].self, from: data)
            Logger.listenBrainz.debug("Loaded \(self.pendingQueue.count, privacy: .public) pending listens from queue")
        } catch {
            Logger.listenBrainz.error("Pending listens queue is corrupt, starting empty: \(error, privacy: .public)")
            pendingQueue = []
        }
    }

    private func saveQueue() {
        let dir = queueFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let data = try JSONEncoder().encode(pendingQueue)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            Logger.listenBrainz.error("Failed to save pending listens queue: \(error, privacy: .public)")
        }
    }

    private func enqueue(_ listen: PendingListen) {
        pendingQueue.append(listen)
        saveQueue()
        Logger.listenBrainz.debug("Enqueued pending listen; queue size=\(self.pendingQueue.count, privacy: .public)")
    }

    // MARK: - Helpers

    /// Trims whitespace and strips trailing slashes for consistent path joining.
    nonisolated static func normalizeServerURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
