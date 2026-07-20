// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

// MARK: - PlaylistSyncClient

/// Minimal protocol over the two SwiftSonic calls used by WrappedPlaylistService.
/// SwiftSonicClient satisfies every requirement via its existing methods (empty conformance below).
nonisolated protocol PlaylistSyncClient: Sendable {
    func getPlaylists(username: String?) async throws -> [Playlist]
    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs
}

extension SwiftSonicClient: PlaylistSyncClient {}

// MARK: - WrappedYearlyPlaylist

nonisolated struct WrappedYearlyPlaylist: Sendable, Identifiable {
    let id: String
    let year: Int
    let name: String
    let coverArtId: String?
}

// MARK: - SyncResult

nonisolated enum SyncResult: Sendable, Equatable {
    case upToDate
    case updated(tracksCount: Int)
    case skippedNoData
    case serverError(String)
}

// MARK: - WrappedPlaylistService

/// Maintains the annual "Cassette Wrapped <year>" server playlist.
///
/// Runs monthly: computes top 100 tracks for the current year via StatsService,
/// then replaces the playlist contents atomically via SwiftSonic createPlaylist
/// replace mode. All persistence is either in UserDefaults (WrappedPreferences)
/// or on the server — no SwiftData access.
actor WrappedPlaylistService {
    nonisolated static let wrappedPlaylistNamePrefix = "Cassette Wrapped "

    private let statsService: StatsService
    private let preferences: WrappedPreferences
    private let makeClient: @Sendable () async throws -> any PlaylistSyncClient
    private let serverService: (any ServerServiceProtocol)?

    /// Production init — captures serverService in the client factory closure.
    init(
        serverService: any ServerServiceProtocol,
        statsService: StatsService,
        preferences: WrappedPreferences = WrappedPreferences()
    ) {
        self.statsService = statsService
        self.preferences = preferences
        self.serverService = serverService
        self.makeClient = { try await serverService.makeSwiftSonicClient() }
    }

    /// Test init — accepts a pre-built client factory for full isolation.
    init(
        clientFactory: @escaping @Sendable () async throws -> any PlaylistSyncClient,
        statsService: StatsService,
        preferences: WrappedPreferences
    ) {
        self.statsService = statsService
        self.preferences = preferences
        self.serverService = nil
        self.makeClient = clientFactory
    }

    // MARK: - Public API

    /// Replaces the annual "Cassette Wrapped <year>" playlist with the top 100
    /// tracks listened to so far this year. Idempotent within a calendar month:
    /// a second call in the same month returns `.upToDate` without a server round-trip.
    func runYearlyPlaylistSyncIfNeeded(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async -> SyncResult {
        let year = calendar.component(.year, from: currentDate)
        let currentYearMonth = YearMonth(year: year, month: calendar.component(.month, from: currentDate))

        if let last = preferences.lastUpdatedMonth(serverId: serverId), last >= currentYearMonth {
            Logger.wrapped.debug("[WRAPPED-SYNC] up-to-date last=\(last, privacy: .public) current=\(currentYearMonth, privacy: .public)")
            return .upToDate
        }

        Logger.wrapped.debug("[WRAPPED-SYNC] start year=\(year, privacy: .public) serverId=\(serverId, privacy: .public)")

        let tracks = await statsService.topTracks(forPeriod: .year(year), serverId: serverId, limit: 100, calendar: calendar)
        Logger.wrapped.debug("[WRAPPED-SYNC] top tracks count=\(tracks.count, privacy: .public)")

        guard !tracks.isEmpty else {
            preferences.setLastUpdatedMonth(currentYearMonth, serverId: serverId)
            Logger.wrapped.debug("[WRAPPED-SYNC] no data for year=\(year, privacy: .public) — skipped")
            return .skippedNoData
        }

        let client: any PlaylistSyncClient
        do {
            client = try await makeClient()
        } catch {
            Logger.wrapped.error("[WRAPPED-SYNC] client init failed: \(error, privacy: .public)")
            return .serverError(error.localizedDescription)
        }

        let pid: String
        do {
            pid = try await getOrCreatePlaylist(for: year, serverId: serverId, client: client)
        } catch {
            Logger.wrapped.error("[WRAPPED-SYNC] getOrCreatePlaylist failed: \(error, privacy: .public)")
            return .serverError(error.localizedDescription)
        }

        let trackIds = tracks.map(\.trackId)
        do {
            try await replacePlaylistTracks(playlistId: pid, trackIds: trackIds, client: client)
        } catch {
            Logger.wrapped.error("[WRAPPED-SYNC] replace playlist failed: \(error, privacy: .public)")
            return .serverError(error.localizedDescription)
        }

        await uploadWrappedCover(year: year, playlistId: pid)

        preferences.setLastUpdatedMonth(currentYearMonth, serverId: serverId)
        preferences.setLastWrappedYear(year, serverId: serverId)
        Logger.wrapped.info("[WRAPPED-SYNC] updated year=\(year, privacy: .public) tracks=\(tracks.count, privacy: .public) playlist=\(pid, privacy: .public)")
        return .updated(tracksCount: tracks.count)
    }

    /// Returns the cached server playlist ID for the given year, or nil if the playlist
    /// has not yet been created by a sync run.
    func playlistId(year: Int, serverId: String) -> String? {
        preferences.playlistId(year: year, serverId: serverId)
    }

    /// Checks whether the calendar year has advanced since the last recorded marker.
    /// When it has, clears the monthly idempotence key so the sync runs fresh for
    /// the new year, then updates the year marker. No-op if already current.
    func handleYearTransitionIfNeeded(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async {
        let currentYear = calendar.component(.year, from: currentDate)
        if let last = preferences.lastWrappedYear(serverId: serverId), last >= currentYear { return }
        preferences.clearLastUpdatedMonth(serverId: serverId)
        preferences.setLastWrappedYear(currentYear, serverId: serverId)
        Logger.wrapped.info("Year marker → \(currentYear, privacy: .public) (serverId=\(serverId, privacy: .public))")
    }

    /// Returns all server playlists whose names match the wrapped prefix, sorted by year descending.
    func fetchYearlyPlaylists(
        serverId: String,
        calendar: Calendar = .current,
        currentDate: Date = Date()
    ) async -> [WrappedYearlyPlaylist] {
        let client: any PlaylistSyncClient
        do {
            client = try await makeClient()
        } catch {
            Logger.wrapped.error("[WRAPPED] fetchYearlyPlaylists client init failed: \(error, privacy: .public)")
            return []
        }
        do {
            let all = try await client.getPlaylists(username: nil)
            // The playlist list is already in hand, so reconciliation costs nothing extra: if the
            // id we cached for this year's playlist is no longer on the server, it was deleted out
            // from under us (a server rebuild wipes playlists). Clearing the cached id and the
            // month marker lets the next cold-start sync recreate it — otherwise the marker keeps
            // the sync from ever running and the playlist stays gone for good.
            reconcileCurrentYearPlaylist(serverId: serverId, livePlaylists: all, calendar: calendar, currentDate: currentDate)
            return all.compactMap { playlist -> WrappedYearlyPlaylist? in
                guard playlist.name.hasPrefix(WrappedPlaylistService.wrappedPlaylistNamePrefix),
                      let year = Int(playlist.name.dropFirst(WrappedPlaylistService.wrappedPlaylistNamePrefix.count))
                else { return nil }
                return WrappedYearlyPlaylist(id: playlist.id, year: year, name: playlist.name, coverArtId: playlist.coverArt)
            }
            .sorted { $0.year > $1.year }
        } catch {
            Logger.wrapped.error("[WRAPPED] fetchYearlyPlaylists failed: \(error, privacy: .public)")
            return []
        }
    }

    // MARK: - Replace playlist tracks

    /// Atomically replaces a playlist's entire track list using the SwiftSonic
    /// createPlaylist replace mode: passing a non-nil playlistId sets the full
    /// song list in one call without a prior fetch.
    private func replacePlaylistTracks(
        playlistId: String,
        trackIds: [String],
        client: any PlaylistSyncClient
    ) async throws {
        _ = try await client.createPlaylist(name: nil, playlistId: playlistId, songIds: trackIds)
        Logger.wrapped.debug("[WRAPPED-SYNC] replaced playlist=\(playlistId, privacy: .public) with \(trackIds.count, privacy: .public) tracks")
    }

    // MARK: - Cover art upload

    private func uploadWrappedCover(year: Int, playlistId: String) async {
        guard let serverService else { return }
        let snapshot = await MainActor.run { serverService.state.activeServer }
        guard let snapshot, let baseURL = URL(string: snapshot.baseURL) else { return }

        let jpegData = await MainActor.run {
            WrappedCoverRenderer.generateCoverData(year: year)
        }
        guard let jpegData else {
            Logger.wrapped.warning("[WRAPPED] Cover generation failed for \(year, privacy: .public)")
            return
        }

        do {
            let creds = try await serverService.activeCredentials()
            let api = NavidromeNativeAPI(transport: CustomHeadersTransport(headers: creds.customHeaders))
            let token = try await api.authenticate(
                baseURL: baseURL,
                username: snapshot.username,
                password: creds.password
            )
            try await api.uploadPlaylistCover(
                baseURL: baseURL,
                token: token,
                playlistId: playlistId,
                imageData: jpegData,
                mimeType: "image/jpeg"
            )
            Logger.wrapped.info("[WRAPPED] Cover uploaded for \(year, privacy: .public) playlist")
        } catch {
            Logger.wrapped.warning("[WRAPPED] Cover upload failed — \(error, privacy: .public)")
        }
    }

    /// Clears the cached id and month marker when this year's playlist has vanished from the server,
    /// so the sync rebuilds it on the next launch. A no-op unless we hold a cached id that is absent
    /// from `livePlaylists` — the normal case touches nothing.
    private func reconcileCurrentYearPlaylist(
        serverId: String,
        livePlaylists: [Playlist],
        calendar: Calendar,
        currentDate: Date
    ) {
        let year = calendar.component(.year, from: currentDate)
        guard let cached = preferences.playlistId(year: year, serverId: serverId) else { return }
        guard !livePlaylists.contains(where: { $0.id == cached }) else { return }
        preferences.clearPlaylistId(year: year, serverId: serverId)
        preferences.clearLastUpdatedMonth(serverId: serverId)
        Logger.wrapped.info("[WRAPPED] \(year, privacy: .public) playlist \(cached, privacy: .public) gone from server — cleared markers so it rebuilds next launch")
    }

    // MARK: - Get-or-create annual playlist

    private func getOrCreatePlaylist(for year: Int, serverId: String, client: any PlaylistSyncClient) async throws -> String {
        let name = "Cassette Wrapped \(year)"
        // Fetch the live list first and trust the cached id ONLY if it is still on the server.
        // A cached id that points to a deleted playlist (server rebuilt, or the user removed it)
        // would otherwise be handed straight to the replace, which writes into nothing. This is the
        // only path where getOrCreatePlaylist runs — once a month — so the extra fetch is cheap.
        let playlists = try await client.getPlaylists(username: nil)

        if let cached = preferences.playlistId(year: year, serverId: serverId),
           playlists.contains(where: { $0.id == cached }) {
            return cached
        }

        if let existing = playlists.first(where: { $0.name == name }) {
            preferences.setPlaylistId(existing.id, year: year, serverId: serverId)
            Logger.wrapped.info("Found '\(name, privacy: .public)' id=\(existing.id, privacy: .public)")
            return existing.id
        }

        let created = try await client.createPlaylist(name: name, playlistId: nil, songIds: [])
        preferences.setPlaylistId(created.id, year: year, serverId: serverId)
        Logger.wrapped.info("Created '\(name, privacy: .public)' id=\(created.id, privacy: .public) (serverId=\(serverId, privacy: .public))")
        return created.id
    }
}
