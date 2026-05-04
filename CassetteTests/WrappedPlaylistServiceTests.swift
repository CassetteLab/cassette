// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
import SwiftSonic
@testable import Cassette

// MARK: - Test infrastructure

enum WrappedTestError: Error { case generic }

final actor MockPlaylistSyncClient: PlaylistSyncClient {
    // Configurable responses
    var playlists: [Playlist] = []

    // Per-method error injection
    var getPlaylistsError: Error?
    var createPlaylistError: Error?

    // Call tracking
    private(set) var getPlaylistsCalls: Int = 0
    private(set) var createPlaylistCalls: [(name: String?, playlistId: String?, songIds: [String])] = []

    private var createCount = 0

    func getPlaylists(username: String?) async throws -> [Playlist] {
        getPlaylistsCalls += 1
        if let err = getPlaylistsError { throw err }
        return playlists
    }

    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs {
        if let err = createPlaylistError { throw err }
        createPlaylistCalls.append((name: name, playlistId: playlistId, songIds: songIds))
        // Replace mode: preserve the given id. Create mode: generate a new one.
        let returnId: String
        if let pid = playlistId {
            returnId = pid
        } else {
            createCount += 1
            returnId = "pl-created-\(createCount)"
        }
        return PlaylistWithSongs(id: returnId, name: name ?? "", songCount: songIds.count, duration: 0)
    }
}

// MARK: - File-scope helpers

private var wrappedCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func wDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = hour
    c.timeZone = TimeZone(identifier: "UTC")!
    return Calendar(identifier: .gregorian).date(from: c)!
}

private func makeStats() throws -> StatsService {
    let container = try ModelContainer.cassette(inMemory: true)
    return StatsService(modelContainer: container)
}

private func makePrefs() -> WrappedPreferences {
    WrappedPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
}

private func makeService(
    mock: MockPlaylistSyncClient,
    stats: StatsService,
    prefs: WrappedPreferences
) -> WrappedPlaylistService {
    WrappedPlaylistService(clientFactory: { mock }, statsService: stats, preferences: prefs)
}

private func makeEvent(
    trackId: String,
    timestamp: Date,
    serverId: String = "srv",
    durationListened: TimeInterval = 200
) -> PlaybackEventDTO {
    PlaybackEventDTO(
        trackId: trackId,
        trackTitle: "Track \(trackId)",
        albumId: nil,
        albumTitle: nil,
        artistId: nil,
        artistName: "Artist",
        genre: nil,
        timestamp: timestamp,
        durationListened: durationListened,
        trackDuration: durationListened + 10,
        wasCompleted: true,
        serverId: serverId
    )
}

// testNow: May 4, 2026 → year=2026, currentYearMonth=2026-05
private let testNow = wDate(year: 2026, month: 5, day: 4)

// MARK: - Suite

@Suite("WrappedPlaylistService Yearly Sync")
struct WrappedPlaylistServiceTests {

    // a: first sync with events — creates playlist then replaces with SET TOTAL
    @Test func firstSync_createsPlaylist_thenReplacesSetTotal() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        for i in 1...3 {
            await stats.recordPlayback(makeEvent(
                trackId: "track-\(i)",
                timestamp: wDate(year: 2026, month: 3, day: i),
                durationListened: TimeInterval(300 - i * 10)
            ))
        }

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(tracksCount: 3))

        let creates = await mock.createPlaylistCalls
        // 2 calls: first creates the empty playlist, second replaces it
        #expect(creates.count == 2)
        #expect(creates[0].name == "Cassette Wrapped 2026")
        #expect(creates[0].playlistId == nil)
        #expect(creates[0].songIds.isEmpty)
        #expect(creates[1].name == nil)
        #expect(creates[1].playlistId == prefs.playlistId(year: 2026, serverId: "srv"))
        #expect(creates[1].songIds.count == 3)

        #expect(prefs.lastUpdatedMonth(serverId: "srv") == YearMonth(year: 2026, month: 5))
        #expect(prefs.lastWrappedYear(serverId: "srv") == 2026)
    }

    // b: idempotence — second call in the same calendar month returns upToDate with no server calls
    @Test func idempotence_sameMonth_returnsUpToDate_noServerCalls() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        _ = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )
        let callsAfterFirst = await mock.createPlaylistCalls.count

        let second = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(second == .upToDate)
        let callsAfterSecond = await mock.createPlaylistCalls.count
        #expect(callsAfterSecond == callsAfterFirst)
    }

    // c: SET TOTAL — second sync in a new month replaces via createPlaylist with existing playlistId
    @Test func setTotal_secondSync_newMonth_replacesExistingPlaylist() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        // First sync in February: Jan event exists
        await stats.recordPlayback(makeEvent(trackId: "jan-t", timestamp: wDate(year: 2026, month: 1, day: 15)))
        _ = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: wDate(year: 2026, month: 2, day: 1)
        )

        let cachedId = prefs.playlistId(year: 2026, serverId: "srv")
        #expect(cachedId != nil)

        // Second sync in May: Apr event added
        await stats.recordPlayback(makeEvent(trackId: "apr-t", timestamp: wDate(year: 2026, month: 4, day: 15)))
        _ = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        let creates = await mock.createPlaylistCalls
        let replaceCalls = creates.filter { $0.playlistId == cachedId }
        // Both the Feb and May syncs issued a replace call with the same playlistId
        #expect(replaceCalls.count == 2)
        // The May replace contains ALL year tracks (SET TOTAL — not just the new Apr track)
        #expect(replaceCalls.last!.songIds.count == 2)
        // Second sync reused the cached id and skipped getPlaylists
        let getCount = await mock.getPlaylistsCalls
        #expect(getCount == 1)
    }

    // d: skippedNoData — no events → flag set, no server calls
    @Test func noEvents_returnsSkippedNoData_flagSet_noServerCalls() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .skippedNoData)
        let creates = await mock.createPlaylistCalls
        #expect(creates.isEmpty)
        // Month is marked even on skip to avoid re-running until next month
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == YearMonth(year: 2026, month: 5))
    }

    // e1: createPlaylist throws → serverError, month NOT marked (sync is retentable)
    @Test func createPlaylistThrows_serverError_monthNotMarked() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        // Pre-cache playlist id so only the replace call is made, isolating the failure
        prefs.setPlaylistId("pl-existing", year: 2026, serverId: "srv")
        await mock.setCreatePlaylistError(WrappedTestError.generic)
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        guard case .serverError = result else {
            Issue.record("Expected serverError, got \(result)")
            return
        }
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == nil)
    }

    // e2: getPlaylists throws → serverError, month NOT marked
    @Test func getPlaylistsThrows_serverError_monthNotMarked() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        await mock.setGetPlaylistsError(WrappedTestError.generic)
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        guard case .serverError = result else {
            Issue.record("Expected serverError, got \(result)")
            return
        }
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == nil)
    }

    // f: multi-server isolation — srvA sync does not affect srvB state
    @Test func multiServerIsolation() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        await stats.recordPlayback(makeEvent(
            trackId: "a-t1", timestamp: wDate(year: 2026, month: 3, day: 1), serverId: "srvA"
        ))

        let resultA = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srvA", calendar: wrappedCal, currentDate: testNow
        )
        let resultB = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srvB", calendar: wrappedCal, currentDate: testNow
        )

        #expect(resultA == .updated(tracksCount: 1))
        #expect(resultB == .skippedNoData)
        #expect(prefs.playlistId(year: 2026, serverId: "srvA") != nil)
        #expect(prefs.playlistId(year: 2026, serverId: "srvB") == nil)
        #expect(prefs.lastUpdatedMonth(serverId: "srvA") == YearMonth(year: 2026, month: 5))
        #expect(prefs.lastUpdatedMonth(serverId: "srvB") == YearMonth(year: 2026, month: 5))
    }

    // h: top-100 limit — 110 tracks seeded, only 100 sent to the replace call
    @Test func top100Limit_moreThan100Tracks_only100InReplaceCall() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        for i in 1...110 {
            await stats.recordPlayback(makeEvent(
                trackId: "t\(i)",
                timestamp: wDate(year: 2026, month: 3, day: 1),
                durationListened: TimeInterval(1000 - i)
            ))
        }

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(tracksCount: 100))

        let creates = await mock.createPlaylistCalls
        let replaceCall = creates.first { $0.playlistId != nil }
        #expect(replaceCall?.songIds.count == 100)
    }
}

// MARK: - MockPlaylistSyncClient mutation helpers

extension MockPlaylistSyncClient {
    func setGetPlaylistsError(_ error: Error?) { getPlaylistsError = error }
    func setCreatePlaylistError(_ error: Error?) { createPlaylistError = error }
}
