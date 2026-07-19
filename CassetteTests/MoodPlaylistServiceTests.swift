// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Stubs

/// Records every call and replays a per-mood outcome keyed on the mood.
private final class ProviderStub: MoodTrackProvider, @unchecked Sendable {
    enum Outcome { case tracks(Int), empty, failure }

    private let lock = NSLock()
    private var _requested: [Mood] = []
    private var _prepares = 0
    var outcomes: [Mood: Outcome] = [:]
    var defaultOutcome: Outcome = .tracks(75)
    var kind: MoodSourceKind = .sonic

    var requested: [Mood] { lock.withLock { _requested } }
    var prepares: Int { lock.withLock { _prepares } }

    func prepare() async { lock.withLock { _prepares += 1 } }

    func trackIds(for mood: Mood, limit: Int) async throws -> [String] {
        lock.withLock { _requested.append(mood) }
        switch outcomes[mood] ?? defaultOutcome {
        case .tracks(let n): return (0..<n).map { "track-\($0)" }
        case .empty:         return []
        case .failure:       throw AudioMuseError.transport("stubbed failure")
        }
    }
}

private final class PlaylistStub: PlaylistSyncClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _replacements: [(playlistId: String, songIds: [String])] = []
    private var _created: [String] = []
    var existing: [Playlist] = []
    var failWrites = false
    /// Emulates a server that accepts the call but stores none of the ids — the failure mode a
    /// foreign id format produces.
    var storesNothing = false

    var replacements: [(playlistId: String, songIds: [String])] { lock.withLock { _replacements } }
    var created: [String] { lock.withLock { _created } }

    func getPlaylists(username: String?) async throws -> [Playlist] { existing }

    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs {
        if failWrites { throw URLError(.badServerResponse) }
        let id = playlistId ?? "created-\(name ?? "?")"
        lock.withLock {
            if playlistId == nil { _created.append(name ?? "?") } else { _replacements.append((id, songIds)) }
        }
        let stored = storesNothing ? 0 : songIds.count
        return try JSONDecoder().decode(
            PlaylistWithSongs.self,
            from: Data(#"{"id":"\#(id)","name":"\#(name ?? "")","songCount":\#(stored),"duration":0}"#.utf8)
        )
    }
}

// MARK: - Harness

/// Records every cover the service asks to be applied.
private final class CoverStub: @unchecked Sendable {
    private let lock = NSLock()
    private var _applied: [(spec: PlaylistGradientSpec, playlistId: String)] = []
    var applied: [(spec: PlaylistGradientSpec, playlistId: String)] { lock.withLock { _applied } }

    func apply(_ spec: PlaylistGradientSpec, _ playlistId: String) {
        lock.withLock { _applied.append((spec, playlistId)) }
    }
}

private struct Harness {
    let provider = ProviderStub()
    let playlists = PlaylistStub()
    let covers = CoverStub()
    let defaults: UserDefaults
    let preferences: MoodPreferences
    let service: MoodPlaylistService
    let serverId = "server-1"

    init() {
        // Swift Testing runs suites in parallel — every harness needs its own defaults domain.
        let name = "mood.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        preferences = MoodPreferences(userDefaults: defaults)
        let provider = provider, playlists = playlists, covers = covers
        service = MoodPlaylistService(
            playlistClientFactory: { playlists },
            providerFactory: { provider },
            coverApplier: { spec, playlistId in covers.apply(spec, playlistId) },
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

        #expect(outcome == .finished(source: .sonic, refreshed: Mood.allCases, kept: []))
        #expect(h.provider.requested.count == 5)
        #expect(h.playlists.replacements.count == 5)
        #expect(h.provider.prepares == 1, "prepare runs once per batch, not per mood")
    }

    @Test("a second run in the same week does nothing at all")
    func secondRunSameWeekIsANoOp() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)
        let outcome = await h.service.runWeeklySyncIfNeeded(
            serverId: h.serverId, calendar: utc, currentDate: date("2026-07-19T08:00:00Z"))

        #expect(outcome == .upToDate)
        #expect(h.provider.requested.count == 5, "no second round of searches")
    }

    @Test("the next Wednesday refreshes again")
    func newCycleRefreshes() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)
        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: nextWednesday)

        #expect(outcome == .finished(source: .sonic, refreshed: Mood.allCases, kept: []))
        #expect(h.playlists.replacements.count == 10)
    }

    @Test("a mood whose search fails keeps its playlist and is retried next launch")
    func failedMoodKeepsItsPlaylist() async {
        let h = Harness()
        h.provider.outcomes[.workout] = .failure

        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(outcome == .finished(source: .sonic, refreshed: Mood.allCases.filter { $0 != .workout }, kept: [.workout]))
        // Four playlists rewritten — Workout's was never touched, so last week's is still there.
        #expect(h.playlists.replacements.count == 4)
        #expect(h.preferences.syncedCycle(mood: .workout, serverId: h.serverId) == nil)
        #expect(h.preferences.syncedCycle(mood: .chill, serverId: h.serverId) != nil)
    }

    @Test("an empty search result never empties the playlist")
    func emptyResultIsNotWritten() async {
        let h = Harness()
        h.provider.outcomes[.night] = .empty

        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(outcome == .finished(source: .sonic, refreshed: Mood.allCases.filter { $0 != .night }, kept: [.night]))
        #expect(!h.playlists.replacements.contains { $0.songIds.isEmpty })
    }

    @Test("only the moods that failed are retried on the next launch")
    func retryCoversOnlyTheFailures() async {
        let h = Harness()
        h.provider.outcomes[.workout] = .failure
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        h.provider.outcomes.removeValue(forKey: .workout)
        // Past the throttle window, still inside the same week.
        let outcome = await h.service.runWeeklySyncIfNeeded(
            serverId: h.serverId, calendar: utc, currentDate: wednesday.addingTimeInterval(7200))

        #expect(outcome == .finished(source: .sonic, refreshed: [.workout], kept: []))
        #expect(h.provider.requested.filter { $0 == .chill }.count == 1, "a succeeded mood is not re-queried")
    }

    @Test("a failing sync is throttled rather than retried on every launch")
    func failuresAreThrottled() async {
        let h = Harness()
        h.provider.defaultOutcome = .failure
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)
        let requestedAfterFirst = h.provider.requested.count

        let outcome = await h.service.runWeeklySyncIfNeeded(
            serverId: h.serverId, calendar: utc, currentDate: wednesday.addingTimeInterval(60))

        #expect(outcome == .throttled)
        #expect(h.provider.requested.count == requestedAfterFirst, "no calls made while throttled")
    }

    @Test("a failing playlist write leaves the mood's marker untouched")
    func playlistWriteFailureKeepsMarker() async {
        let h = Harness()
        h.playlists.failWrites = true

        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(outcome == .finished(source: .sonic, refreshed: [], kept: Mood.allCases))
        for mood in Mood.allCases {
            #expect(h.preferences.syncedCycle(mood: mood, serverId: h.serverId) == nil)
        }
    }

    @Test("a server that stores none of the ids counts as a failure, not a success")
    func serverStoringNothingIsAFailure() async {
        // Navidrome answers 200 and silently drops ids it does not recognise, so a whole batch of
        // foreign ids produced an empty playlist that we reported as "refreshed with 75 tracks".
        let h = Harness()
        h.playlists.storesNothing = true

        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(outcome == .finished(source: .sonic, refreshed: [], kept: Mood.allCases))
        for mood in Mood.allCases {
            #expect(h.preferences.syncedCycle(mood: mood, serverId: h.serverId) == nil,
                    "\(mood.rawValue) must be retried, not marked done")
        }
        #expect(h.covers.applied.isEmpty, "no cover for a playlist that was never written")
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
            providerFactory: { nil },
            preferences: MoodPreferences(userDefaults: UserDefaults(suiteName: "mood.tests.\(UUID().uuidString)")!)
        )
        let outcome = await service.runWeeklySyncIfNeeded(serverId: "s", calendar: utc, currentDate: wednesday)

        #expect(outcome == .notConfigured)
        #expect(playlists.replacements.isEmpty)
    }

    @Test("each mood is requested exactly once")
    func everyMoodRequestedOnce() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(Set(h.provider.requested) == Set(Mood.allCases))
        #expect(h.provider.requested.count == 5)
    }

    @Test("the source that populated the playlists is recorded for the UI")
    func sourceIsRecorded() async {
        let h = Harness()
        h.provider.kind = .tags
        let outcome = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(outcome == .finished(source: .tags, refreshed: Mood.allCases, kept: []))
        #expect(await h.service.lastSource(serverId: h.serverId) == .tags)
    }

    // MARK: - Covers

    @Test("each playlist gets its generated cover on first build")
    func coversAreAppliedOnce() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(h.covers.applied.count == 5)
        // Distinct specs: same colour on two moods would make them indistinguishable as thumbnails.
        let specs = h.covers.applied.map(\.spec)
        for (i, spec) in specs.enumerated() {
            #expect(!specs[(i + 1)...].contains(spec), "two moods share a cover design")
        }
    }

    @Test("the cover is not re-uploaded on later refreshes")
    func coversAreNotReapplied() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: nextWednesday)

        #expect(h.covers.applied.count == 5, "the cover never changes — uploading it weekly is waste")
    }

    @Test("a mood that failed gets no cover")
    func failedMoodGetsNoCover() async {
        let h = Harness()
        h.provider.outcomes[.workout] = .failure
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        #expect(h.covers.applied.count == 4)
    }

    // MARK: - Forced rebuild

    @Test("a forced rebuild rewrites every playlist even mid-week")
    func rebuildIgnoresTheCadence() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)
        #expect(h.playlists.replacements.count == 5)

        // Connecting AudioMuse two days later must not leave the tag-built playlists in place
        // until the following Wednesday.
        let outcome = await h.service.rebuildNow(
            serverId: h.serverId, calendar: utc, currentDate: date("2026-07-17T10:00:00Z"))

        #expect(outcome == .finished(source: .sonic, refreshed: Mood.allCases, kept: []))
        #expect(h.playlists.replacements.count == 10)
    }

    @Test("a forced rebuild bypasses the throttle")
    func rebuildIgnoresTheThrottle() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)

        // One minute later — well inside the throttle window, which a normal call would refuse.
        let outcome = await h.service.rebuildNow(
            serverId: h.serverId, calendar: utc, currentDate: wednesday.addingTimeInterval(60))

        #expect(outcome != .throttled)
        #expect(h.playlists.replacements.count == 10)
    }

    @Test("a forced rebuild reuses the existing playlists rather than creating new ones")
    func rebuildKeepsPlaylistIds() async {
        let h = Harness()
        _ = await h.service.runWeeklySyncIfNeeded(serverId: h.serverId, calendar: utc, currentDate: wednesday)
        let createdFirst = h.playlists.created.count

        _ = await h.service.rebuildNow(serverId: h.serverId, calendar: utc, currentDate: wednesday.addingTimeInterval(60))

        #expect(h.playlists.created.count == createdFirst, "rebuilding must not orphan the old playlists")
    }

    @Test("every mood carries a distinct English prompt for the sonic provider")
    func promptsAreDistinct() {
        let queries = Mood.allCases.map(\.query)
        #expect(Set(queries).count == queries.count)
        // ASCII-only is the check that matters: these are fed to CLAP, which embeds against
        // English, so a localised prompt would quietly degrade every match.
        #expect(queries.allSatisfy { $0.allSatisfy(\.isASCII) })
    }
}
