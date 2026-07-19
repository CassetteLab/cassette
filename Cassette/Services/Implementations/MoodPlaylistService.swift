// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

// MARK: - MoodSearchClient

/// The slice of AudioMuse the mood sync needs. Lets tests drive the whole service without a server.
nonisolated protocol MoodSearchClient: Sendable {
    @discardableResult func warmup() async -> Bool
    func search(query: String, limit: Int) async throws -> [AudioMuseTrack]
}

extension AudioMuseClient: MoodSearchClient {}

// MARK: - Results

nonisolated enum MoodSyncOutcome: Sendable, Equatable {
    /// AudioMuse is not set up for this server — the feature is simply absent, not broken.
    case notConfigured
    /// Every mood already refreshed for the current week.
    case upToDate
    /// An attempt was made too recently; backing off rather than retrying a dead endpoint.
    case throttled
    case finished(refreshed: [Mood], kept: [Mood])
}

/// Why a single mood was left alone. Its previous playlist stays exactly as it was.
nonisolated enum MoodSkipReason: Error, Sendable, Equatable {
    case searchFailed(String)
    case noResults
    case playlistWriteFailed(String)
}

// MARK: - MoodPlaylistService

/// Maintains five server-side mood playlists, refreshed weekly from AudioMuse's sonic search.
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
/// - **Warmup first.** AudioMuse evicts the CLAP model after ten minutes idle, so a weekly job
///   always arrives cold.
actor MoodPlaylistService {
    private let preferences: MoodPreferences
    private let makePlaylistClient: @Sendable () async throws -> any PlaylistSyncClient
    private let makeSearchClient: @Sendable () async -> (any MoodSearchClient)?

    /// Minimum gap between attempts, so an unreachable instance is not re-probed every launch.
    static let attemptThrottle: TimeInterval = 3600

    init(
        playlistClientFactory: @escaping @Sendable () async throws -> any PlaylistSyncClient,
        searchClientFactory: @escaping @Sendable () async -> (any MoodSearchClient)?,
        preferences: MoodPreferences = MoodPreferences()
    ) {
        self.makePlaylistClient = playlistClientFactory
        self.makeSearchClient = searchClientFactory
        self.preferences = preferences
    }

    /// Production wiring: both clients are derived from the active server's configuration.
    init(serverService: any ServerServiceProtocol, serverState: ServerState, preferences: MoodPreferences = MoodPreferences()) {
        self.preferences = preferences
        self.makePlaylistClient = { try await serverService.makeSwiftSonicClient() }
        self.makeSearchClient = {
            guard let urlString = await MainActor.run(body: { serverState.activeServer?.audioMuseURL }),
                  let credentials = try? await serverService.activeCredentials() else { return nil }
            return AudioMuseClient(urlString: urlString, token: credentials.audioMuseToken)
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

        guard let search = await makeSearchClient() else { return .notConfigured }
        preferences.setLastAttempt(currentDate, serverId: serverId)

        let playlists: any PlaylistSyncClient
        do {
            playlists = try await makePlaylistClient()
        } catch {
            Logger.moodPlaylists.error("[MOOD-SYNC] no Subsonic client: \(error, privacy: .public)")
            return .finished(refreshed: [], kept: pending)
        }

        // Cold model: pay the load once, up front, instead of inside the first mood's timeout.
        await search.warmup()

        var refreshed: [Mood] = []
        var kept: [Mood] = []
        for mood in pending {
            do {
                try await refresh(mood, serverId: serverId, cycle: cycle, search: search, playlists: playlists)
                refreshed.append(mood)
            } catch let reason as MoodSkipReason {
                kept.append(mood)
                Logger.moodPlaylists.warning("[MOOD-SYNC] \(mood.rawValue, privacy: .public) kept its previous playlist: \(String(describing: reason), privacy: .public)")
            } catch {
                kept.append(mood)
                Logger.moodPlaylists.warning("[MOOD-SYNC] \(mood.rawValue, privacy: .public) kept its previous playlist: \(error, privacy: .public)")
            }
        }

        Logger.moodPlaylists.info("[MOOD-SYNC] refreshed \(refreshed.count, privacy: .public)/\(pending.count, privacy: .public) — kept \(kept.map(\.rawValue).joined(separator: ","), privacy: .public)")
        return .finished(refreshed: refreshed, kept: kept)
    }

    /// One mood, end to end. Throws `MoodSkipReason` so the caller can keep going; the marker is
    /// only advanced once the server has accepted the new track list.
    private func refresh(
        _ mood: Mood,
        serverId: String,
        cycle: Date,
        search: any MoodSearchClient,
        playlists: any PlaylistSyncClient
    ) async throws {
        let tracks: [AudioMuseTrack]
        do {
            tracks = try await search.search(query: mood.query, limit: Mood.trackCount)
        } catch {
            throw MoodSkipReason.searchFailed(String(describing: error))
        }
        // An empty result is not a reason to empty the playlist — the index may simply be
        // rebuilding. Keep what is there.
        guard !tracks.isEmpty else { throw MoodSkipReason.noResults }

        do {
            let playlistId = try await resolvePlaylistId(for: mood, serverId: serverId, client: playlists)
            // createPlaylist with a non-nil id replaces the whole track list in one call — no
            // read-modify-write, so the playlist is never briefly empty.
            _ = try await playlists.createPlaylist(name: nil, playlistId: playlistId, songIds: tracks.map(\.itemId))
            preferences.setPlaylistId(playlistId, mood: mood, serverId: serverId)
        } catch {
            throw MoodSkipReason.playlistWriteFailed(String(describing: error))
        }

        preferences.setSyncedCycle(cycle, mood: mood, serverId: serverId)
        Logger.moodPlaylists.info("[MOOD-SYNC] \(mood.rawValue, privacy: .public) refreshed with \(tracks.count, privacy: .public) tracks")
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

    /// Clears local state when the user disconnects AudioMuse. The server playlists are left in
    /// place — they are the user's now, and deleting them would be a surprise.
    func forgetLocalState(serverId: String) {
        preferences.reset(serverId: serverId)
    }
}
