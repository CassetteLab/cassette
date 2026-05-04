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
    var existingEntries: [Song] = []

    // Per-method error injection
    var getPlaylistsError: Error?
    var getPlaylistError: Error?
    var createPlaylistError: Error?
    var updatePlaylistError: Error?

    // Call tracking
    private(set) var getPlaylistsCalls: Int = 0
    private(set) var createPlaylistCalls: [String?] = []
    private(set) var getPlaylistCalls: [String] = []
    private(set) var updatePlaylistCalls: [(id: String, songIdsToAdd: [String])] = []

    private var createCount = 0

    func getPlaylists(username: String?) async throws -> [Playlist] {
        getPlaylistsCalls += 1
        if let err = getPlaylistsError { throw err }
        return playlists
    }

    func getPlaylist(id: String) async throws -> PlaylistWithSongs {
        getPlaylistCalls.append(id)
        if let err = getPlaylistError { throw err }
        return PlaylistWithSongs(id: id, name: "", songCount: existingEntries.count, duration: 0, entry: existingEntries)
    }

    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs {
        if let err = createPlaylistError { throw err }
        createCount += 1
        let newId = "pl-created-\(createCount)"
        createPlaylistCalls.append(name)
        return PlaylistWithSongs(id: newId, name: name ?? "", songCount: 0, duration: 0)
    }

    func updatePlaylist(id: String, name: String?, comment: String?, isPublic: Bool?, songIdsToAdd: [String], songIndexesToRemove: [Int]) async throws {
        if let err = updatePlaylistError { throw err }
        updatePlaylistCalls.append((id: id, songIdsToAdd: songIdsToAdd))
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

// currentDate used in all single-month tests: May 4 2026 → previousMonth = April 2026
private let testNow = wDate(year: 2026, month: 5, day: 4)

// MARK: - Suite

@Suite("WrappedPlaylistService Monthly Update")
struct WrappedPlaylistServiceTests {

    // a1: no events → skippedNoData, zero server calls
    @Test func noEvents_returnsSkippedNoData_noServerCalls() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .skippedNoData)
        let updates = await mock.updatePlaylistCalls
        #expect(updates.isEmpty)
        let creates = await mock.createPlaylistCalls
        #expect(creates.isEmpty)
    }

    // a2: events exist → playlist created, tracks added, month marked
    @Test func withEvents_updatesPlaylist() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        // Process only April by setting lastUpdated to March
        prefs.setLastUpdatedMonth(YearMonth(string: "2026-03")!, serverId: "srv")

        // Seed April events
        for i in 1...3 {
            await stats.recordPlayback(makeEvent(
                trackId: "track-\(i)",
                timestamp: wDate(year: 2026, month: 4, day: i),
                durationListened: TimeInterval(300 - i * 10)
            ))
        }

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(monthsProcessed: 1, tracksAdded: 3))

        let creates = await mock.createPlaylistCalls
        #expect(creates.count == 1)
        #expect(creates[0] == "Cassette Wrapped 2026")

        let updates = await mock.updatePlaylistCalls
        #expect(updates.count == 1)
        #expect(updates[0].songIdsToAdd.count == 3)

        let marked = prefs.lastUpdatedMonth(serverId: "srv")
        #expect(marked == YearMonth(string: "2026-04"))
    }

    // b: second run after successful update returns upToDate, no new server calls
    @Test func idempotence_secondRunIsNoOp() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(string: "2026-03")!, serverId: "srv")

        await stats.recordPlayback(makeEvent(
            trackId: "t1", timestamp: wDate(year: 2026, month: 4, day: 1)
        ))

        _ = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )
        let updateCountAfterFirst = await mock.updatePlaylistCalls.count

        let second = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(second == .upToDate)
        let updateCountAfterSecond = await mock.updatePlaylistCalls.count
        #expect(updateCountAfterSecond == updateCountAfterFirst)
    }

    // c: catch-up three months: one playlist created, three updates
    @Test func catchUp_threeMonths_onePlaylistThreeUpdates() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(string: "2026-01")!, serverId: "srv")

        for (month, trackId) in [(2, "feb-t"), (3, "mar-t"), (4, "apr-t")] {
            await stats.recordPlayback(makeEvent(
                trackId: trackId,
                timestamp: wDate(year: 2026, month: month, day: 15)
            ))
        }

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(monthsProcessed: 3, tracksAdded: 3))

        let creates = await mock.createPlaylistCalls
        #expect(creates.count == 1)
        #expect(creates[0] == "Cassette Wrapped 2026")

        let updates = await mock.updatePlaylistCalls
        #expect(updates.count == 3)

        let marked = prefs.lastUpdatedMonth(serverId: "srv")
        #expect(marked == YearMonth(string: "2026-04"))
    }

    // d: empty month in the middle is skipped but marked done; surrounding months processed
    @Test func emptyMonthInMiddle_skippedAndMarkedDone() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(string: "2026-01")!, serverId: "srv")

        // Feb and Apr have events; Mar is intentionally empty
        await stats.recordPlayback(makeEvent(trackId: "feb-t", timestamp: wDate(year: 2026, month: 2, day: 15)))
        await stats.recordPlayback(makeEvent(trackId: "apr-t", timestamp: wDate(year: 2026, month: 4, day: 15)))

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(monthsProcessed: 2, tracksAdded: 2))

        // Mar (no-data) must not trigger any updatePlaylist; only Feb and Apr should
        let updates = await mock.updatePlaylistCalls
        #expect(updates.count == 2)

        let marked = prefs.lastUpdatedMonth(serverId: "srv")
        #expect(marked == YearMonth(string: "2026-04"))
    }

    // e1: trackA already in playlist → only new trackC is added
    @Test func partialDedup_onlyNewTracksAdded() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(string: "2026-03")!, serverId: "srv")

        // Existing playlist contains trackA
        await mock.setExistingEntries([Song(id: "trackA", title: "Track A")])

        // Both trackA and trackC appear in top tracks (trackA longer → higher rank)
        await stats.recordPlayback(makeEvent(trackId: "trackA", timestamp: wDate(year: 2026, month: 4, day: 1), durationListened: 300))
        await stats.recordPlayback(makeEvent(trackId: "trackC", timestamp: wDate(year: 2026, month: 4, day: 2), durationListened: 200))

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(monthsProcessed: 1, tracksAdded: 1))

        let updates = await mock.updatePlaylistCalls
        #expect(updates.count == 1)
        #expect(updates[0].songIdsToAdd == ["trackC"])
    }

    // e2: all top tracks already in playlist → skipped, no updatePlaylist call
    @Test func allDuplicates_skipped_noUpdateCall() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(string: "2026-03")!, serverId: "srv")

        await mock.setExistingEntries([
            Song(id: "trackA", title: "A"),
            Song(id: "trackB", title: "B")
        ])

        await stats.recordPlayback(makeEvent(trackId: "trackA", timestamp: wDate(year: 2026, month: 4, day: 1), durationListened: 300))
        await stats.recordPlayback(makeEvent(trackId: "trackB", timestamp: wDate(year: 2026, month: 4, day: 2), durationListened: 200))

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .skippedNoData)

        let updates = await mock.updatePlaylistCalls
        #expect(updates.isEmpty)
    }

    // f: playlist already has 117 tracks → only 3 slots remain out of 10 new tracks
    @Test func cap120Tracks_onlyRemainingSlotsFilled() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(string: "2026-03")!, serverId: "srv")

        let existing = (1...117).map { Song(id: "ex-\($0)", title: "Existing \($0)") }
        await mock.setExistingEntries(existing)

        // 10 distinct new tracks, each with unique decreasing duration for stable ranking
        for i in 1...10 {
            await stats.recordPlayback(makeEvent(
                trackId: "new-\(i)",
                timestamp: wDate(year: 2026, month: 4, day: i),
                durationListened: TimeInterval(300 - i * 5)
            ))
        }

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(monthsProcessed: 1, tracksAdded: 3))

        let updates = await mock.updatePlaylistCalls
        #expect(updates.count == 1)
        #expect(updates[0].songIdsToAdd.count == 3)
    }

    // g1: createPlaylist throws → serverError, month not marked
    @Test func createPlaylistThrows_serverError_monthNotMarked() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(string: "2026-03")!, serverId: "srv")
        await mock.setCreatePlaylistError(WrappedTestError.generic)

        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 4, day: 1)))

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .serverError(WrappedTestError.generic))
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == YearMonth(string: "2026-03"))
    }

    // g2: updatePlaylist throws → serverError, month not marked
    @Test func updatePlaylistThrows_serverError_monthNotMarked() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(string: "2026-03")!, serverId: "srv")
        await mock.setUpdatePlaylistError(WrappedTestError.generic)

        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 4, day: 1)))

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .serverError(WrappedTestError.generic))
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == YearMonth(string: "2026-03"))
    }

    // g3: getPlaylists throws → serverError, month not marked
    @Test func getPlaylistsThrows_serverError_monthNotMarked() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(string: "2026-03")!, serverId: "srv")
        await mock.setGetPlaylistsError(WrappedTestError.generic)

        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 4, day: 1)))

        let result = await service.runMonthlyUpdateIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .serverError(WrappedTestError.generic))
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == YearMonth(string: "2026-03"))
    }

    // h: two servers share one service — each server's state is fully isolated
    @Test func multiServerIsolation() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        // srvA: has events for April
        prefs.setLastUpdatedMonth(YearMonth(string: "2026-03")!, serverId: "srvA")
        await stats.recordPlayback(makeEvent(
            trackId: "a-t1", timestamp: wDate(year: 2026, month: 4, day: 1), serverId: "srvA"
        ))

        // srvB: no events, no lastUpdated (processes Jan-Apr, all empty)
        let resultA = await service.runMonthlyUpdateIfNeeded(
            serverId: "srvA", calendar: wrappedCal, currentDate: testNow
        )
        let resultB = await service.runMonthlyUpdateIfNeeded(
            serverId: "srvB", calendar: wrappedCal, currentDate: testNow
        )

        #expect(resultA == .updated(monthsProcessed: 1, tracksAdded: 1))
        #expect(resultB == .skippedNoData)

        // srvA has playlist cached; srvB does not (skipped before any playlist API call)
        #expect(prefs.playlistId(year: 2026, serverId: "srvA") != nil)
        #expect(prefs.playlistId(year: 2026, serverId: "srvB") == nil)
    }
}

// MARK: - MockPlaylistSyncClient mutation helpers
// Async setters used in tests to mutate mock state before exercising the service.

extension MockPlaylistSyncClient {
    func setExistingEntries(_ songs: [Song]) { existingEntries = songs }
    func setGetPlaylistsError(_ error: Error?) { getPlaylistsError = error }
    func setCreatePlaylistError(_ error: Error?) { createPlaylistError = error }
    func setUpdatePlaylistError(_ error: Error?) { updatePlaylistError = error }
}
