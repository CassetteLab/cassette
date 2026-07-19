// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Stubs

/// Records every call and replays a per-mood outcome keyed on the query string.
private final class SearchStub: MoodSearchClient, @unchecked Sendable {
    enum Outcome { case tracks(Int), empty, failure }

    private let lock = NSLock()
    private var _queries: [String] = []
    private var _warmups = 0
    var outcomes: [String: Outcome] = [:]
    var defaultOutcome: Outcome = .tracks(75)

    var queries: [String] { lock.withLock { _queries } }
    var warmups: Int { lock.withLock { _warmups } }

    func warmup() async -> Bool { lock.withLock { _warmups += 1 }; return true }

    func search(query: String, limit: Int) async throws -> [AudioMuseTrack] {
        lock.withLock { _queries.append(query) }
        switch outcomes[query] ?? defaultOutcome {
        case .tracks(let n):
            return (0..<n).map { AudioMuseTrack(itemId: "track-\($0)", title: nil, author: nil, similarity: nil) }
        case .empty:
            return []
        case .failure:
            throw AudioMuseError.transport("stubbed failure")
        }
    }
}

private final class PlaylistStub: PlaylistSyncClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _replacements: [(playlistId: String, songIds: [String])] = []
    private var _created: [String] = []
    var existing: [Playlist] = []
    var failWrites = false

    var replacements: [(playlistId: String, songIds: [String])] { lock.withLock { _replacements } }
    var created: [String] { lock.withLock { _created } }

    func getPlaylists(username: String?) async throws -> [Playlist] { existing }

    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs {
        if failWrites { throw URLError(.badServerResponse) }
        let id = playlistId ?? "created-\(name ?? "?")"
        lock.withLock {
            if playlistId == nil { _created.append(name ?? "?") } else { _replacements.append((id, songIds)) }
        }
        return try JSONDecoder().decode(
            PlaylistWithSongs.self,
            from: Data(#"{"id":"\#(id)","name":"\#(name ?? "")","songCount":0,"duration":0}"#.utf8)
        )
    }
}

// MARK: - Harness

private struct Harness {
    let search = SearchStub()
    let playlists = PlaylistStub()
    let defaults: UserDefaults
    let preferences: MoodPreferences
    let service: MoodPlaylistService
    let serverId = "server-1"

    init() {
        // Swift Testing runs suites in parallel — every harness needs its own defaults domain.
        let name = "mood.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        preferences = MoodPreferences(userDefaults: defaults)
        let search = search, playlists = playlists
        service = MoodPlaylistService(
            playlistClientFactory: { playlists },
            searchClientFactory: { search },
            preferences: preferences
        )
    }
}

/// Fixed clock: Wednesday 2026-07-15 12:00 UTC, and the Friday after it.
private func date(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}
private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

// MARK: - Cycle

@Suite("Mood playlists — weekly cycle")
struct MoodCycleTests {

    @Test("the cycle starts on the Wednesday of the current week")
    func wednesdayIsTheAnchor() {
        // Wed 15th → itself; Thu 16th and Tue 21st → still the 15th; Wed 22nd → a new cycle.
        let wednesday = MoodCycle.start(for: date("2026-07-15T12:00:00Z"), calendar: utc)
        #expect(MoodCycle.start(for: date("2026-07-16T09:00:00Z"), calendar: utc) == wednesday)
        #expect(MoodCycle.start(for: date("2026-07-21T23:59:00Z"), calendar: utc) == wednesday)
        #expect(MoodCycle.start(for: date("2026-07-22T00:01:00Z"), calendar: utc) > wednesday)
    }

    @Test("a Tuesday belongs to the previous Wednesday's cycle, not the coming one")
    func tuesdayLooksBackward() {
        let tuesday = MoodCycle.start(for: date("2026-07-21T10:00:00Z"), calendar: utc)
        #expect(utc.component(.day, from: tuesday) == 15)
    }

    @Test("the cycle start is midnight, so a same-day second launch is up to date")
    func startIsMidnight() {
        let start = MoodCycle.start(for: date("2026-07-15T23:30:00Z"), calendar: utc)
        #expect(utc.component(.hour, from: start) == 0)
        #expect(utc.component(.minute, from: start) == 0)
    }
}

// MARK: - Sync

@Suite("Mood playlists — weekly sync")
struct MoodPlaylistServiceTests {

    private let wednesday = date("2026-07-15T12:00:00Z")
    private let nextWednesday = date("2026-07-22T12:00:00Z")

    @Test("a first run refreshes all five moods")
    func firstRunRefreshesEverything() async {
        let h = Harness()
        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(outcome == .finished(refreshed: Mood.allCases, kept: []))
        #expect(h.search.queries.count == 5)
        #expect(h.playlists.replacements.count == 5)
        #expect(h.search.warmups == 1, "the CLAP model must be warmed once, not per mood")
    }

    @Test("a second run in the same week does nothing at all")
    func secondRunSameWeekIsANoOp() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)
        let outcome = await h.service.runWeeklySyncIfNeeded(
            serverId: h.serverId, calendar: utc, currentDate: date("2026-07-19T08:00:00Z"))

        #expect(outcome == .upToDate)
        #expect(h.search.queries.count == 5, "no second round of searches")
    }

    @Test("the next Wednesday refreshes again")
    func newCycleRefreshes() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)
        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: nextWednesday)

        #expect(outcome == .finished(refreshed: Mood.allCases, kept: []))
        #expect(h.playlists.replacements.count == 10)
    }

    @Test("a mood whose search fails keeps its playlist and is retried next launch")
    func failedMoodKeepsItsPlaylist() async {
        let h = Harness()
        h.search.outcomes[Mood.workout.query] = .failure

        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(outcome == .finished(refreshed: Mood.allCases.filter { $0 != .workout }, kept: [.workout]))
        // Four playlists rewritten — Workout's was never touched, so last week's is still there.
        #expect(h.playlists.replacements.count == 4)
        #expect(h.preferences.syncedCycle(mood: .workout, serverId: h.serverId) == nil)
        #expect(h.preferences.syncedCycle(mood: .chill, serverId: h.serverId) != nil)
    }

    @Test("an empty search result never empties the playlist")
    func emptyResultIsNotWritten() async {
        let h = Harness()
        h.search.outcomes[Mood.night.query] = .empty

        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(outcome == .finished(refreshed: Mood.allCases.filter { $0 != .night }, kept: [.night]))
        #expect(!h.playlists.replacements.contains { $0.songIds.isEmpty })
    }

    @Test("only the moods that failed are retried on the next launch")
    func retryCoversOnlyTheFailures() async {
        let h = Harness()
        h.search.outcomes[Mood.workout.query] = .failure
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        h.search.outcomes.removeValue(forKey: Mood.workout.query)
        // Past the throttle window, still inside the same week.
        let outcome = await h.service.runWeeklySyncIfNeeded(
            serverId: h.serverId, calendar: utc, currentDate: wednesday.addingTimeInterval(7200))

        #expect(outcome == .finished(refreshed: [.workout], kept: []))
        #expect(h.search.queries.filter { $0 == Mood.chill.query }.count == 1, "a succeeded mood is not re-queried")
    }

    @Test("a failing sync is throttled rather than retried on every launch")
    func failuresAreThrottled() async {
        let h = Harness()
        h.search.defaultOutcome = .failure
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)
        let queriesAfterFirst = h.search.queries.count

        let outcome = await h.service.runWeeklySyncIfNeeded(
            serverId: h.serverId, calendar: utc, currentDate: wednesday.addingTimeInterval(60))

        #expect(outcome == .throttled)
        #expect(h.search.queries.count == queriesAfterFirst, "no calls made while throttled")
    }

    @Test("a failing playlist write leaves the mood's marker untouched")
    func playlistWriteFailureKeepsMarker() async {
        let h = Harness()
        h.playlists.failWrites = true

        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(outcome == .finished(refreshed: [], kept: Mood.allCases))
        for mood in Mood.allCases {
            #expect(h.preferences.syncedCycle(mood: mood, serverId: h.serverId) == nil)
        }
    }

    @Test("an existing server playlist is reused instead of creating a duplicate")
    func existingPlaylistIsReused() async throws {
        let h = Harness()
        h.playlists.existing = try Mood.allCases.map { mood in
            try JSONDecoder().decode(
                Playlist.self,
                from: Data(#"{"id":"existing-\#(mood.rawValue)","name":"\#(mood.playlistName)","songCount":0,"duration":0}"#.utf8)
            )
        }

        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(h.playlists.created.isEmpty, "reinstalling must not leave a second copy of each playlist")
        #expect(h.playlists.replacements.allSatisfy { $0.playlistId.hasPrefix("existing-") })
    }

    @Test("no AudioMuse configured means the feature is simply absent")
    func notConfigured() async {
        let playlists = PlaylistStub()
        let service = MoodPlaylistService(
            playlistClientFactory: { playlists },
            searchClientFactory: { nil },
            preferences: MoodPreferences(userDefaults: UserDefaults(suiteName: "mood.tests.\(UUID().uuidString)")!)
        )
        let outcome = await service.runWeeklySyncIfNeeded(serverId: "s", calendar: utc, currentDate: wednesday)

        #expect(outcome == .notConfigured)
        #expect(playlists.replacements.isEmpty)
    }

    @Test("each mood sends its own English prompt")
    func promptsAreDistinctAndEnglish() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(Set(h.search.queries).count == 5)
        #expect(Set(h.search.queries) == Set(Mood.allCases.map(\.query)))
    }
}
