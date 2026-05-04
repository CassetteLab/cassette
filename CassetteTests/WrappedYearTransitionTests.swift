// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
@testable import Cassette

// MARK: - File-scope helpers

private var ytCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func ytDate(year: Int, month: Int, day: Int) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = 12
    c.timeZone = TimeZone(identifier: "UTC")!
    return Calendar(identifier: .gregorian).date(from: c)!
}

private func ytMakeStats() throws -> StatsService {
    let container = try ModelContainer.cassette(inMemory: true)
    return StatsService(modelContainer: container)
}

private func ytMakePrefs() -> WrappedPreferences {
    WrappedPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
}

private func ytMakeService(
    mock: MockPlaylistSyncClient,
    stats: StatsService,
    prefs: WrappedPreferences
) -> WrappedPlaylistService {
    WrappedPlaylistService(clientFactory: { mock }, statsService: stats, preferences: prefs)
}

private func ytMakeEvent(trackId: String, timestamp: Date, serverId: String = "srv") -> PlaybackEventDTO {
    PlaybackEventDTO(
        trackId: trackId,
        trackTitle: "Track \(trackId)",
        albumId: nil,
        albumTitle: nil,
        artistId: nil,
        artistName: "Artist",
        genre: nil,
        timestamp: timestamp,
        durationListened: 200,
        trackDuration: 210,
        wasCompleted: true,
        serverId: serverId
    )
}

// MARK: - Year Transition Suite

@Suite("WrappedPlaylistService Year Transition")
struct WrappedYearTransitionTests {

    // i1: no prior year marker → sets current year
    @Test func lastYearNil_setsCurrentYear() async throws {
        let prefs = ytMakePrefs()
        let mock = MockPlaylistSyncClient()
        let stats = try ytMakeStats()
        let service = ytMakeService(mock: mock, stats: stats, prefs: prefs)

        #expect(prefs.lastWrappedYear(serverId: "srv") == nil)

        await service.handleYearTransitionIfNeeded(
            serverId: "srv", calendar: ytCal, currentDate: ytDate(year: 2026, month: 5, day: 4)
        )

        #expect(prefs.lastWrappedYear(serverId: "srv") == 2026)
    }

    // i2: prior year < current year → advances to current year
    @Test func lastYear2025_current2026_updatesToCurrentYear() async throws {
        let prefs = ytMakePrefs()
        let mock = MockPlaylistSyncClient()
        let stats = try ytMakeStats()
        let service = ytMakeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastWrappedYear(2025, serverId: "srv")

        await service.handleYearTransitionIfNeeded(
            serverId: "srv", calendar: ytCal, currentDate: ytDate(year: 2026, month: 1, day: 10)
        )

        #expect(prefs.lastWrappedYear(serverId: "srv") == 2026)
    }

    // i3: prior year == current year → no-op
    @Test func lastYear2026_current2026_isNoOp() async throws {
        let prefs = ytMakePrefs()
        let mock = MockPlaylistSyncClient()
        let stats = try ytMakeStats()
        let service = ytMakeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastWrappedYear(2026, serverId: "srv")

        await service.handleYearTransitionIfNeeded(
            serverId: "srv", calendar: ytCal, currentDate: ytDate(year: 2026, month: 6, day: 1)
        )

        // Value remains 2026 — confirmed unchanged
        #expect(prefs.lastWrappedYear(serverId: "srv") == 2026)
    }

    // j: December 2025 events land in "Cassette Wrapped 2025",
    //    January 2026 events land in "Cassette Wrapped 2026"
    @Test func yearBascule_decemberUsesCurrentYearPlaylist_januaryCreatesNextYear() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try ytMakeStats()
        let prefs = ytMakePrefs()
        let service = ytMakeService(mock: mock, stats: stats, prefs: prefs)

        // Seed events for both months upfront
        await stats.recordPlayback(ytMakeEvent(trackId: "dec-t", timestamp: ytDate(year: 2025, month: 12, day: 15)))
        await stats.recordPlayback(ytMakeEvent(trackId: "jan-t", timestamp: ytDate(year: 2026, month: 1, day: 15)))

        // Run 1: currentDate = Jan 10 2026 → previousMonth = Dec 2025 (year 2025)
        prefs.setLastUpdatedMonth(YearMonth(string: "2025-11")!, serverId: "srv")
        _ = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: ytCal, currentDate: ytDate(year: 2026, month: 1, day: 10)
        )

        // Run 2: currentDate = Feb 10 2026 → previousMonth = Jan 2026 (year 2026)
        _ = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: ytCal, currentDate: ytDate(year: 2026, month: 2, day: 10)
        )

        let creates = await mock.createPlaylistCalls
        #expect(creates.count == 2)
        #expect(creates[0] == "Cassette Wrapped 2025")
        #expect(creates[1] == "Cassette Wrapped 2026")
    }
}

// MARK: - WrappedPreferences Suite

@Suite("WrappedPreferences")
struct WrappedPreferencesTests {

    // k1: lastUpdatedMonth round-trip
    @Test func lastUpdatedMonth_roundTrip() {
        let prefs = ytMakePrefs()
        let ym = YearMonth(year: 2026, month: 4)

        #expect(prefs.lastUpdatedMonth(serverId: "srv") == nil)

        prefs.setLastUpdatedMonth(ym, serverId: "srv")
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == ym)
    }

    // k2: playlistId round-trip
    @Test func playlistId_roundTrip() {
        let prefs = ytMakePrefs()

        #expect(prefs.playlistId(year: 2026, serverId: "srv") == nil)

        prefs.setPlaylistId("pl-abc", year: 2026, serverId: "srv")
        #expect(prefs.playlistId(year: 2026, serverId: "srv") == "pl-abc")
    }

    // k3: lastWrappedYear round-trip
    @Test func lastWrappedYear_roundTrip() {
        let prefs = ytMakePrefs()

        #expect(prefs.lastWrappedYear(serverId: "srv") == nil)

        prefs.setLastWrappedYear(2026, serverId: "srv")
        #expect(prefs.lastWrappedYear(serverId: "srv") == 2026)
    }

    // k4: multi-server keys are independent
    @Test func multiServer_keysAreIsolated() {
        let prefs = ytMakePrefs()

        prefs.setLastUpdatedMonth(YearMonth(year: 2026, month: 3), serverId: "srvA")
        prefs.setPlaylistId("pl-A", year: 2026, serverId: "srvA")
        prefs.setLastWrappedYear(2026, serverId: "srvA")

        // srvB untouched
        #expect(prefs.lastUpdatedMonth(serverId: "srvB") == nil)
        #expect(prefs.playlistId(year: 2026, serverId: "srvB") == nil)
        #expect(prefs.lastWrappedYear(serverId: "srvB") == nil)

        // srvA unaffected by srvB reads
        #expect(prefs.lastUpdatedMonth(serverId: "srvA") == YearMonth(year: 2026, month: 3))
        #expect(prefs.playlistId(year: 2026, serverId: "srvA") == "pl-A")
        #expect(prefs.lastWrappedYear(serverId: "srvA") == 2026)
    }
}
