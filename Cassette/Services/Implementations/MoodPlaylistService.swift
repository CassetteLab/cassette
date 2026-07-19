// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

// MARK: - Results

nonisolated enum MoodSyncOutcome: Sendable, Equatable {
    /// No provider at all. Not reachable in production — the tag provider always exists — but kept
    /// so tests can exercise the branch and so a future provider can opt out.
    case notConfigured
    /// Every mood already refreshed for the current week.
    case upToDate
    /// An attempt was made too recently; backing off rather than retrying a dead endpoint.
    case throttled
    case finished(source: MoodSourceKind, refreshed: [Mood], kept: [Mood])
}

/// Why a single mood was left alone. Its previous playlist stays exactly as it was.
nonisolated enum MoodSkipReason: Error, Sendable, Equatable {
    case searchFailed(String)
    case noResults
    case playlistWriteFailed(String)
    /// The server accepted the call and stored none of it — every track id was foreign to it.
    /// `sample` carries a few of the ids so the mismatch is visible in the log.
    case serverStoredNothing(sent: Int, sample: [String])
}

// MARK: - MoodPlaylistService

/// Maintains five server-side mood playlists, refreshed weekly.
///
/// Tracks come from AudioMuse's sonic analysis when it is configured, and from the server's own
/// MOOD/genre/BPM tags when it is not — so the feature exists on every server, and is better on
/// some. The choice is made once per run and recorded, because it changes how good the result is
/// and the user deserves to know which one they got.
///
/// Modelled on WrappedPlaylistService: a cadence marker in UserDefaults, playlists owned by the
/// server, and atomic replacement through createPlaylist's replace mode. The differences that
/// matter:
///
/// - **Five independent units of work.** A mood that fails keeps its old playlist and its old
///   marker, so the user still has last week's Workout rather than an empty one, and it retries by
///   itself. Nothing is ever cleared on failure.
/// - **Sequential, not parallel.** Instant Mix taught us that concurrent similarity queries on a
///   self-hosted box contend hard — eight parallel calls each took 22s against 12.8s solo. Five
///   moods one after another is friendlier and, on that evidence, probably not slower.
/// - **A prepare step.** AudioMuse evicts the CLAP model after ten minutes idle, so a weekly job
///   always arrives cold and pays the load up front rather than inside the first mood's timeout.
actor MoodPlaylistService {
    private let preferences: MoodPreferences
    private let makePlaylistClient: @Sendable () async throws -> any PlaylistSyncClient
    private let makeProvider: @Sendable () async -> (any MoodTrackProvider)?
    /// Renders and applies a playlist cover. Injected rather than called directly because
    /// PlaylistCoverManager is MainActor-bound and this is an actor.
    private let applyCover: (@Sendable (PlaylistGradientSpec, String) async -> Void)?

    /// Minimum gap between attempts, so an unreachable instance is not re-probed every launch.
    static let attemptThrottle: TimeInterval = 3600

    init(
        playlistClientFactory: @escaping @Sendable () async throws -> any PlaylistSyncClient,
        providerFactory: @escaping @Sendable () async -> (any MoodTrackProvider)?,
        coverApplier: (@Sendable (PlaylistGradientSpec, String) async -> Void)? = nil,
        preferences: MoodPreferences = MoodPreferences()
    ) {
        self.makePlaylistClient = playlistClientFactory
        self.makeProvider = providerFactory
        self.applyCover = coverApplier
        self.preferences = preferences
    }

    /// Production wiring. AudioMuse when it is configured and reachable-looking, the server's own
    /// tags otherwise — so the moods exist on every server, just better on some.
    init(
        serverService: any ServerServiceProtocol,
        serverState: ServerState,
        libraryService: any LibraryServiceProtocol,
        coverApplier: (@Sendable (PlaylistGradientSpec, String) async -> Void)? = nil,
        preferences: MoodPreferences = MoodPreferences()
    ) {
        self.preferences = preferences
        self.applyCover = coverApplier
        self.makePlaylistClient = { try await serverService.makeSwiftSonicClient() }
        self.makeProvider = {
            if let urlString = await MainActor.run(body: { serverState.activeServer?.audioMuseURL }),
               let credentials = try? await serverService.activeCredentials(),
               let client = AudioMuseClient(urlString: urlString, token: credentials.audioMuseToken) {
                return AudioMuseTrackProvider(client: client, resolver: SubsonicTrackResolver(libraryService: libraryService))
            }
            return LibraryTagTrackProvider(libraryService: libraryService)
        }
    }

    // MARK: - Sync

    /// Refreshes any mood whose playlist predates the current week.
    ///
    /// Safe to call on every launch: it is a no-op once the week's work is done, and throttled when
    /// the last attempt failed recently.
    func runWeeklySyncIfNeeded(
        serverId: String,
        calendar: Calendar = .current,
        currentDate: Date = Date()
    ) async -> MoodSyncOutcome {
        let cycle = MoodCycle.start(for: currentDate, calendar: calendar)
        let pending = Mood.allCases.filter { mood in
            guard let synced = preferences.syncedCycle(mood: mood, serverId: serverId) else { return true }
            return synced < cycle
        }
        guard !pending.isEmpty else { return .upToDate }

        if let last = preferences.lastAttempt(serverId: serverId),
           currentDate.timeIntervalSince(last) < Self.attemptThrottle {
            Logger.moodPlaylists.debug("[MOOD-SYNC] throttled — last attempt \(Int(currentDate.timeIntervalSince(last)), privacy: .public)s ago")
            return .throttled
        }

        guard let provider = await makeProvider() else { return .notConfigured }
        preferences.setLastAttempt(currentDate, serverId: serverId)

        let playlists: any PlaylistSyncClient
        do {
            playlists = try await makePlaylistClient()
        } catch {
            Logger.moodPlaylists.error("[MOOD-SYNC] no Subsonic client: \(error, privacy: .public)")
            return .finished(source: provider.kind, refreshed: [], kept: pending)
        }

        await provider.prepare()

        var refreshed: [Mood] = []
        var kept: [Mood] = []
        for mood in pending {
            do {
                try await refresh(mood, serverId: serverId, cycle: cycle, provider: provider, playlists: playlists)
                refreshed.append(mood)
            } catch let reason as MoodSkipReason {
                kept.append(mood)
                Logger.moodPlaylists.warning("[MOOD-SYNC] \(mood.rawValue, privacy: .public) kept its previous playlist: \(String(describing: reason), privacy: .public)")
            } catch {
                kept.append(mood)
                Logger.moodPlaylists.warning("[MOOD-SYNC] \(mood.rawValue, privacy: .public) kept its previous playlist: \(error, privacy: .public)")
            }
        }

        Logger.moodPlaylists.info("[MOOD-SYNC] source=\(provider.kind.rawValue, privacy: .public) refreshed \(refreshed.count, privacy: .public)/\(pending.count, privacy: .public) — kept \(kept.map(\.rawValue).joined(separator: ","), privacy: .public)")
        preferences.setLastSource(provider.kind, serverId: serverId)
        return .finished(source: provider.kind, refreshed: refreshed, kept: kept)
    }

    /// Rebuilds all five playlists now, whatever the weekly cadence says.
    ///
    /// Called when the track source changes: connecting AudioMuse should replace the tag-built
    /// playlists immediately rather than leaving the user to wonder until Wednesday whether it took
    /// effect. Playlist ids are kept, so the existing playlists are rewritten in place.
    @discardableResult
    func rebuildNow(serverId: String, calendar: Calendar = .current, currentDate: Date = Date()) async -> MoodSyncOutcome {
        preferences.markAllDue(serverId: serverId)
        return await runWeeklySyncIfNeeded(serverId: serverId, calendar: calendar, currentDate: currentDate)
    }

    /// One mood, end to end. Throws `MoodSkipReason` so the caller can keep going; the marker is
    /// only advanced once the server has accepted the new track list.
    private func refresh(
        _ mood: Mood,
        serverId: String,
        cycle: Date,
        provider: any MoodTrackProvider,
        playlists: any PlaylistSyncClient
    ) async throws {
        let trackIds: [String]
        do {
            trackIds = try await provider.trackIds(for: mood, limit: Mood.trackCount)
        } catch {
            throw MoodSkipReason.searchFailed(String(describing: error))
        }
        // An empty result is not a reason to empty the playlist — a sonic index may be rebuilding,
        // or the library may simply have no tagged tracks for this mood. Keep what is there.
        guard !trackIds.isEmpty else { throw MoodSkipReason.noResults }

        let written: Int
        do {
            let playlistId = try await resolvePlaylistId(for: mood, serverId: serverId, client: playlists)
            // createPlaylist with a non-nil id replaces the whole track list in one call — no
            // read-modify-write, so the playlist is never briefly empty.
            let result = try await playlists.createPlaylist(name: nil, playlistId: playlistId, songIds: trackIds)
            written = result.songCount
            preferences.setPlaylistId(playlistId, mood: mood, serverId: serverId)
        } catch {
            throw MoodSkipReason.playlistWriteFailed(String(describing: error))
        }

        // Trust what the server says it stored, not what we sent it. A Subsonic server silently
        // drops track ids it does not recognise and still answers 200, so a whole batch of foreign
        // ids yields an empty playlist and a perfectly successful-looking call. Treating that as a
        // failure keeps the previous playlist and retries, instead of reporting a write that only
        // happened on our side.
        guard written > 0 else {
            throw MoodSkipReason.serverStoredNothing(sent: trackIds.count, sample: Array(trackIds.prefix(3)))
        }
        if written < trackIds.count {
            Logger.moodPlaylists.warning("[MOOD-SYNC] \(mood.rawValue, privacy: .public): server kept \(written, privacy: .public) of \(trackIds.count, privacy: .public) ids — the rest were unknown to it")
        }

        preferences.setSyncedCycle(cycle, mood: mood, serverId: serverId)
        Logger.moodPlaylists.info("[MOOD-SYNC] \(mood.rawValue, privacy: .public) refreshed — server stored \(written, privacy: .public) tracks")

        // Once per playlist, not per refresh: the cover never changes, and re-uploading it every
        // week would be pure waste. Failures are silent — a playlist without its cover still works.
        if let applyCover, !preferences.hasCover(mood: mood, serverId: serverId) {
            let playlistId = preferences.playlistId(mood: mood, serverId: serverId)
            if let playlistId {
                await applyCover(mood.gradientSpec, playlistId)
                preferences.setHasCover(mood: mood, serverId: serverId)
            }
        }
    }

    /// Cached id, else an existing playlist of the same name, else a newly created one.
    ///
    /// The name lookup matters after a reinstall: UserDefaults is gone but the server playlists are
    /// not, and without it every reinstall would leave a second "Cassette · Night" behind.
    private func resolvePlaylistId(for mood: Mood, serverId: String, client: any PlaylistSyncClient) async throws -> String {
        if let cached = preferences.playlistId(mood: mood, serverId: serverId) { return cached }
        if let existing = try await client.getPlaylists(username: nil).first(where: { $0.name == mood.playlistName }) {
            return existing.id
        }
        return try await client.createPlaylist(name: mood.playlistName, playlistId: nil, songIds: []).id
    }

    // MARK: - Read

    /// Server playlist id backing a mood, or nil before its first successful sync.
    func playlistId(for mood: Mood, serverId: String) -> String? {
        preferences.playlistId(mood: mood, serverId: serverId)
    }

    func lastRefresh(serverId: String) -> Date? {
        preferences.lastRefresh(serverId: serverId)
    }

    /// Which source last populated the playlists, for the settings screen to be honest about
    /// whether the user is getting sonic matching or tag matching.
    func lastSource(serverId: String) -> MoodSourceKind? {
        preferences.lastSource(serverId: serverId)
    }

    /// Clears local state when the user disconnects AudioMuse. The server playlists are left in
    /// place — they are the user's now, and deleting them would be a surprise.
    func forgetLocalState(serverId: String) {
        preferences.reset(serverId: serverId)
    }
}
