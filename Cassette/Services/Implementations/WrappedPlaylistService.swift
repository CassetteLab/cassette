// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

// MARK: - MonthlyUpdateResult

nonisolated enum MonthlyUpdateResult: @unchecked Sendable {
    case upToDate
    case updated(monthsProcessed: Int, tracksAdded: Int)
    case skippedNoData
    case serverError(any Error)
}

// MARK: - WrappedPlaylistService

/// Maintains the annual "Cassette Wrapped <year>" server playlist.
///
/// Runs monthly: computes top-10 tracks for the previous month via StatsService,
/// deduplicates against the existing playlist, and appends via SwiftSonic.
/// All persistence is either in UserDefaults (WrappedPreferences) or on the
/// server — no SwiftData access.
actor WrappedPlaylistService {
    private let serverService: any ServerServiceProtocol
    private let statsService: StatsService
    private let preferences: WrappedPreferences

    init(
        serverService: any ServerServiceProtocol,
        statsService: StatsService,
        preferences: WrappedPreferences = WrappedPreferences()
    ) {
        self.serverService = serverService
        self.statsService = statsService
        self.preferences = preferences
    }

    // MARK: - Public API

    /// Determines which past months are missing from the annual playlist and processes
    /// them in order. Idempotent: calling repeatedly is safe due to per-month dedup.
    func runMonthlyUpdateIfNeeded(serverId: String, calendar: Calendar) async -> MonthlyUpdateResult {
        let months = monthsNeedingUpdate(serverId: serverId, calendar: calendar)
        guard !months.isEmpty else {
            Logger.wrapped.debug("Up-to-date (serverId=\(serverId, privacy: .public))")
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

    /// Checks whether the calendar year has advanced since the last recorded marker.
    /// When it has, updates the local year marker so the next monthly update will
    /// create a fresh "Cassette Wrapped <newYear>" playlist automatically.
    /// No-op if already current.
    func handleYearTransitionIfNeeded(serverId: String, calendar: Calendar) async {
        let currentYear = calendar.component(.year, from: Date())
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

    private func monthsNeedingUpdate(serverId: String, calendar: Calendar) -> [YearMonth] {
        let now = Date()
        let cy = calendar.component(.year, from: now)
        let cm = calendar.component(.month, from: now)

        let previousMonth = YearMonth(
            year: cm == 1 ? cy - 1 : cy,
            month: cm == 1 ? 12 : cm - 1
        )

        let startMonth: YearMonth
        if let last = preferences.lastUpdatedMonth(serverId: serverId) {
            startMonth = last.advanced(by: 1)
        } else {
            startMonth = YearMonth(year: cy, month: 1)
        }

        guard startMonth <= previousMonth else { return [] }

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
        let period = WrappedPeriod.month(year: ym.year, month: ym.month)
        let data = await statsService.wrappedData(for: period, serverId: serverId, calendar: calendar)

        guard data.totalTracksPlayed > 0 else {
            preferences.setLastUpdatedMonth(ym, serverId: serverId)
            Logger.wrapped.debug("No data for \(ym, privacy: .public) — skipping (serverId=\(serverId, privacy: .public))")
            return .skipped
        }

        let topTrackIds = data.topTracks.map(\.trackId)
        let playlistId = try await getOrCreatePlaylist(for: ym.year, serverId: serverId)

        let client = try await serverService.makeSwiftSonicClient()
        let currentPlaylist = try await client.getPlaylist(id: playlistId)
        let existingIds = Set((currentPlaylist.entry ?? []).map(\.id))

        let newTrackIds = topTrackIds.filter { !existingIds.contains($0) }
        guard !newTrackIds.isEmpty else {
            preferences.setLastUpdatedMonth(ym, serverId: serverId)
            Logger.wrapped.info("\(ym, privacy: .public) — all tracks already in playlist, skipping")
            return .skipped
        }

        // Cap at 120 tracks total for the annual playlist
        let available = max(0, 120 - existingIds.count)
        let tracksToAdd = Array(newTrackIds.prefix(available))
        guard !tracksToAdd.isEmpty else {
            preferences.setLastUpdatedMonth(ym, serverId: serverId)
            Logger.wrapped.info("\(ym, privacy: .public) — playlist at 120-track cap, skipping")
            return .skipped
        }

        // Mark done ONLY after successful server update (idempotence guarantee)
        try await client.updatePlaylist(id: playlistId, songIdsToAdd: tracksToAdd)
        preferences.setLastUpdatedMonth(ym, serverId: serverId)
        Logger.wrapped.info("Added \(tracksToAdd.count, privacy: .public) tracks for \(ym, privacy: .public) → playlist \(playlistId, privacy: .public)")
        return .processed(tracksAdded: tracksToAdd.count)
    }

    // MARK: - Get-or-create annual playlist

    private func getOrCreatePlaylist(for year: Int, serverId: String) async throws -> String {
        if let cached = preferences.playlistId(year: year, serverId: serverId) {
            return cached
        }

        let client = try await serverService.makeSwiftSonicClient()
        let name = "Cassette Wrapped \(year)"
        let playlists = try await client.getPlaylists()

        if let existing = playlists.first(where: { $0.name == name }) {
            preferences.setPlaylistId(existing.id, year: year, serverId: serverId)
            Logger.wrapped.info("Found '\(name, privacy: .public)' id=\(existing.id, privacy: .public)")
            return existing.id
        }

        let created = try await client.createPlaylist(name: name)
        preferences.setPlaylistId(created.id, year: year, serverId: serverId)
        Logger.wrapped.info("Created '\(name, privacy: .public)' id=\(created.id, privacy: .public) (serverId=\(serverId, privacy: .public))")
        return created.id
    }
}
