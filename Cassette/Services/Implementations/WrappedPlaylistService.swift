// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

// MARK: - PlaylistSyncClient

/// Minimal protocol over the four SwiftSonic calls used by WrappedPlaylistService.
/// SwiftSonicClient satisfies every requirement via its existing methods (empty conformance below).
nonisolated protocol PlaylistSyncClient: Sendable {
    func getPlaylists(username: String?) async throws -> [Playlist]
    func getPlaylist(id: String) async throws -> PlaylistWithSongs
    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs
    func updatePlaylist(id: String, name: String?, comment: String?, isPublic: Bool?, songIdsToAdd: [String], songIndexesToRemove: [Int]) async throws
}

extension SwiftSonicClient: PlaylistSyncClient {}

// MARK: - MonthlyUpdateResult

nonisolated enum MonthlyUpdateResult: @unchecked Sendable, Equatable {
    case upToDate
    case updated(monthsProcessed: Int, tracksAdded: Int)
    case skippedNoData
    case serverError(any Error)

    static func == (lhs: MonthlyUpdateResult, rhs: MonthlyUpdateResult) -> Bool {
        switch (lhs, rhs) {
        case (.upToDate, .upToDate): return true
        case (.skippedNoData, .skippedNoData): return true
        case (.updated(let m1, let t1), .updated(let m2, let t2)): return m1 == m2 && t1 == t2
        case (.serverError, .serverError): return true
        default: return false
        }
    }
}

// MARK: - WrappedPlaylistService

/// Maintains the annual "Cassette Wrapped <year>" server playlist.
///
/// Runs monthly: computes top-10 tracks for the previous month via StatsService,
/// deduplicates against the existing playlist, and appends via SwiftSonic.
/// All persistence is either in UserDefaults (WrappedPreferences) or on the
/// server — no SwiftData access.
actor WrappedPlaylistService {
    private let statsService: StatsService
    private let preferences: WrappedPreferences
    private let makeClient: @Sendable () async throws -> any PlaylistSyncClient

    /// Production init — captures serverService in the client factory closure.
    init(
        serverService: any ServerServiceProtocol,
        statsService: StatsService,
        preferences: WrappedPreferences = WrappedPreferences()
    ) {
        self.statsService = statsService
        self.preferences = preferences
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
        self.makeClient = clientFactory
    }

    // MARK: - Public API

    /// Determines which past months are missing from the annual playlist and processes
    /// them in order. Idempotent: calling repeatedly is safe due to per-month dedup.
    func runYearlyPlaylistSyncIfNeeded(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async -> MonthlyUpdateResult {
        Logger.wrapped.debug("[WRAPPED-SYNC] start update for serverId=\(serverId, privacy: .public)")

        let lastUpdated = preferences.lastUpdatedMonth(serverId: serverId)
        Logger.wrapped.debug("[WRAPPED-FLOW] lastWrappedMonthUpdated read = \(lastUpdated?.description ?? "nil", privacy: .public)")

        let months = monthsNeedingUpdate(serverId: serverId, calendar: calendar, currentDate: currentDate)
        let monthsDesc = months.map(\.description).joined(separator: ", ")
        Logger.wrapped.debug("[WRAPPED-FLOW] months to process: \(months.count, privacy: .public) — [\(monthsDesc, privacy: .public)]")

        guard !months.isEmpty else {
            Logger.wrapped.debug("[WRAPPED-FLOW] decision: UP-TO-DATE, returning early")
            return .upToDate
        }

        Logger.wrapped.info("Processing \(months.count, privacy: .public) month(s) for serverId=\(serverId, privacy: .public)")

        var monthsProcessed = 0
        var totalTracksAdded = 0
        var anyData = false

        for ym in months {
            do {
                let result = try await processMonth(ym, serverId: serverId, calendar: calendar)
                switch result {
                case .processed(let count):
                    anyData = true
                    monthsProcessed += 1
                    totalTracksAdded += count
                case .skipped:
                    break
                }
            } catch {
                Logger.wrapped.error("Server error for \(ym, privacy: .public): \(error, privacy: .public)")
                return .serverError(error)
            }
        }

        guard anyData else { return .skippedNoData }
        return .updated(monthsProcessed: monthsProcessed, tracksAdded: totalTracksAdded)
    }

    /// Returns the cached server playlist ID for the given year, or nil if the playlist
    /// has not yet been created by a monthly update run.
    func playlistId(year: Int, serverId: String) -> String? {
        preferences.playlistId(year: year, serverId: serverId)
    }

    /// Checks whether the calendar year has advanced since the last recorded marker.
    /// When it has, updates the local year marker so the next monthly update will
    /// create a fresh "Cassette Wrapped <newYear>" playlist automatically.
    /// No-op if already current.
    func handleYearTransitionIfNeeded(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async {
        let currentYear = calendar.component(.year, from: currentDate)
        if let last = preferences.lastWrappedYear(serverId: serverId), last >= currentYear { return }
        preferences.setLastWrappedYear(currentYear, serverId: serverId)
        Logger.wrapped.info("Year marker → \(currentYear, privacy: .public) (serverId=\(serverId, privacy: .public))")
    }

    // MARK: - Private types

    private enum ProcessResult {
        case skipped
        case processed(tracksAdded: Int)
    }

    // MARK: - Months calculation

    private func monthsNeedingUpdate(serverId: String, calendar: Calendar, currentDate: Date) -> [YearMonth] {
        let cy = calendar.component(.year, from: currentDate)
        let cm = calendar.component(.month, from: currentDate)

        let previousMonth = YearMonth(
            year: cm == 1 ? cy - 1 : cy,
            month: cm == 1 ? 12 : cm - 1
        )
        Logger.wrapped.debug("[WRAPPED-FLOW] current month = \(String(format: "%04d-%02d", cy, cm), privacy: .public), target (previous closed month) = \(previousMonth, privacy: .public)")

        let startMonth: YearMonth
        if let last = preferences.lastUpdatedMonth(serverId: serverId) {
            startMonth = last.advanced(by: 1)
            Logger.wrapped.debug("[WRAPPED-FLOW] last persisted = \(last, privacy: .public), startMonth = \(startMonth, privacy: .public)")
        } else {
            startMonth = YearMonth(year: cy, month: 1)
            Logger.wrapped.debug("[WRAPPED-FLOW] no persisted state, startMonth = \(startMonth, privacy: .public)")
        }

        guard startMonth <= previousMonth else {
            Logger.wrapped.debug("[WRAPPED-FLOW] startMonth \(startMonth, privacy: .public) > previousMonth \(previousMonth, privacy: .public) → nothing to do")
            return []
        }

        var months: [YearMonth] = []
        var current = startMonth
        while current <= previousMonth {
            months.append(current)
            current = current.advanced(by: 1)
        }
        return months
    }

    // MARK: - Month processing

    private func processMonth(_ ym: YearMonth, serverId: String, calendar: Calendar) async throws -> ProcessResult {
        Logger.wrapped.debug("[WRAPPED-FLOW] processing \(ym, privacy: .public)")
        let period = WrappedPeriod.month(year: ym.year, month: ym.month)
        let data = await statsService.wrappedData(for: period, serverId: serverId, calendar: calendar)
        Logger.wrapped.debug("[WRAPPED-FLOW] wrappedData totalTracksPlayed=\(data.totalTracksPlayed, privacy: .public) topTracks=\(data.topTracks.count, privacy: .public)")

        guard data.totalTracksPlayed > 0 else {
            Logger.wrapped.debug("[WRAPPED-FLOW] decision: SKIP no-data — flag set: lastWrappedMonthUpdated = \(ym, privacy: .public)")
            preferences.setLastUpdatedMonth(ym, serverId: serverId)
            Logger.wrapped.debug("No data for \(ym, privacy: .public) — skipping (serverId=\(serverId, privacy: .public))")
            return .skipped
        }

        Logger.wrapped.debug("[WRAPPED-FLOW] decision: PROCEED — fetching/creating playlist for year \(ym.year, privacy: .public)")
        let topTrackIds = data.topTracks.map(\.trackId)
        Logger.wrapped.debug("[WRAPPED-FLOW] calling getOrCreatePlaylist for year=\(ym.year, privacy: .public)")

        let client = try await makeClient()
        let playlistId = try await getOrCreatePlaylist(for: ym.year, serverId: serverId, client: client)
        Logger.wrapped.debug("[WRAPPED-FLOW] playlistId=\(playlistId, privacy: .public), fetching current entries")

        let currentPlaylist = try await client.getPlaylist(id: playlistId)
        let existingIds = Set((currentPlaylist.entry ?? []).map(\.id))
        Logger.wrapped.debug("[WRAPPED-FLOW] playlist has \(existingIds.count, privacy: .public) existing tracks")

        let newTrackIds = topTrackIds.filter { !existingIds.contains($0) }
        Logger.wrapped.debug("[WRAPPED-FLOW] new (non-duplicate) tracks to consider: \(newTrackIds.count, privacy: .public)")
        guard !newTrackIds.isEmpty else {
            Logger.wrapped.debug("[WRAPPED-FLOW] decision: SKIP all-duplicates — flag set: lastWrappedMonthUpdated = \(ym, privacy: .public)")
            preferences.setLastUpdatedMonth(ym, serverId: serverId)
            Logger.wrapped.info("\(ym, privacy: .public) — all tracks already in playlist, skipping")
            return .skipped
        }

        // Cap at 120 tracks total for the annual playlist
        let available = max(0, 120 - existingIds.count)
        let tracksToAdd = Array(newTrackIds.prefix(available))
        Logger.wrapped.debug("[WRAPPED-FLOW] available slots=\(available, privacy: .public), tracksToAdd=\(tracksToAdd.count, privacy: .public)")
        guard !tracksToAdd.isEmpty else {
            Logger.wrapped.debug("[WRAPPED-FLOW] decision: SKIP 120-cap — flag set: lastWrappedMonthUpdated = \(ym, privacy: .public)")
            preferences.setLastUpdatedMonth(ym, serverId: serverId)
            Logger.wrapped.info("\(ym, privacy: .public) — playlist at 120-track cap, skipping")
            return .skipped
        }

        // Mark done ONLY after successful server update (idempotence guarantee)
        Logger.wrapped.debug("[WRAPPED-FLOW] calling updatePlaylist id=\(playlistId, privacy: .public) adding \(tracksToAdd.count, privacy: .public) tracks")
        try await client.updatePlaylist(
            id: playlistId,
            name: nil,
            comment: nil,
            isPublic: nil,
            songIdsToAdd: tracksToAdd,
            songIndexesToRemove: []
        )
        Logger.wrapped.debug("[WRAPPED-FLOW] flag set: lastWrappedMonthUpdated = \(ym, privacy: .public)")
        preferences.setLastUpdatedMonth(ym, serverId: serverId)
        Logger.wrapped.info("Added \(tracksToAdd.count, privacy: .public) tracks for \(ym, privacy: .public) → playlist \(playlistId, privacy: .public)")
        return .processed(tracksAdded: tracksToAdd.count)
    }

    // MARK: - Get-or-create annual playlist

    private func getOrCreatePlaylist(for year: Int, serverId: String, client: any PlaylistSyncClient) async throws -> String {
        if let cached = preferences.playlistId(year: year, serverId: serverId) {
            return cached
        }

        let name = "Replay \(year)"
        let playlists = try await client.getPlaylists(username: nil)

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
