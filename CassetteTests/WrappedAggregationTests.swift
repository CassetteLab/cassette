// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
@testable import Cassette

// MARK: - Helpers

/// UTC calendar for deterministic timezone-insensitive tests.
private let utcCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

/// Builds a Date in UTC for the given year/month/day/hour.
private func utcDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute; c.second = 0
    c.timeZone = TimeZone(identifier: "UTC")!
    return Calendar(identifier: .gregorian).date(from: c)!
}

private func makeService() throws -> StatsService {
    let container = try ModelContainer.cassette(inMemory: true)
    return StatsService(modelContainer: container)
}

private func makeDTO(
    trackId: String = "t1",
    trackTitle: String = "Track 1",
    artistId: String? = "a1",
    artistName: String = "Artist 1",
    albumId: String? = "alb1",
    albumTitle: String? = "Album 1",
    genre: String? = nil,
    timestamp: Date,
    durationListened: TimeInterval = 180,
    serverId: String = "srv"
) -> PlaybackEventDTO {
    PlaybackEventDTO(
        trackId: trackId,
        trackTitle: trackTitle,
        albumId: albumId,
        albumTitle: albumTitle,
        artistId: artistId,
        artistName: artistName,
        genre: genre,
        timestamp: timestamp,
        durationListened: durationListened,
        trackDuration: durationListened + 10,
        wasCompleted: true,
        serverId: serverId
    )
}

// MARK: - Suite

@Suite("WrappedAggregation")
struct WrappedAggregationTests {

    // a) Empty period
    @Test func emptyPeriod_returnsZeros() async throws {
        let service = try makeService()
        let period = WrappedPeriod.month(year: 2026, month: 1)
        let data = await service.wrappedData(for: period, serverId: "srv", calendar: utcCalendar)

        #expect(data.totalTracksPlayed == 0)
        #expect(data.totalSecondsListened == 0)
        #expect(data.totalUniqueTracks == 0)
        #expect(data.totalUniqueArtists == 0)
        #expect(data.totalUniqueAlbums == 0)
        #expect(data.topTracks.isEmpty)
        #expect(data.topAlbums.isEmpty)
        #expect(data.topArtists.isEmpty)
        #expect(data.dominantGenre == nil)
        #expect(data.streakDays == 0)
        #expect(data.firstTrackOfPeriod == nil)
        #expect(data.lastTrackOfPeriod == nil)
    }

    // b) Single event
    @Test func singleEvent_producesCorrectTotalsAndTops() async throws {
        let service = try makeService()
        let ts = utcDate(year: 2026, month: 3, day: 10)
        await service.recordPlayback(makeDTO(timestamp: ts, durationListened: 240))

        let period = WrappedPeriod.month(year: 2026, month: 3)
        let data = await service.wrappedData(for: period, serverId: "srv", calendar: utcCalendar)

        #expect(data.totalTracksPlayed == 1)
        #expect(data.totalSecondsListened == 240)
        #expect(data.totalUniqueTracks == 1)
        #expect(data.topTracks.count == 1)
        #expect(data.topTracks[0].rank == 1)
        #expect(data.topTracks[0].playCount == 1)
        #expect(data.topTracks[0].totalSecondsListened == 240)
        #expect(data.topAlbums.count == 1)
        #expect(data.topArtists.count == 1)
    }

    // c) Multiple events same track: grouped, summed
    @Test func sameTrack_multipleEvents_grouped() async throws {
        let service = try makeService()
        let base = utcDate(year: 2026, month: 3, day: 1)
        for i in 0..<3 {
            await service.recordPlayback(makeDTO(
                timestamp: Calendar.current.date(byAdding: .day, value: i, to: base)!,
                durationListened: 100
            ))
        }

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )

        #expect(data.totalTracksPlayed == 3)
        #expect(data.totalUniqueTracks == 1)
        #expect(data.topTracks.count == 1)
        #expect(data.topTracks[0].playCount == 3)
        #expect(data.topTracks[0].totalSecondsListened == 300)
    }

    // d) Top 10 cap: 15 distinct tracks, returns top 10 by duration
    @Test func topTracks_cappedAt10_sortedByDuration() async throws {
        let service = try makeService()
        let base = utcDate(year: 2026, month: 3, day: 1)
        for i in 1...15 {
            // Track i gets i*10 seconds so track-15 is longest
            await service.recordPlayback(makeDTO(
                trackId: "t\(i)",
                trackTitle: "Track \(i)",
                timestamp: Calendar.current.date(byAdding: .hour, value: i, to: base)!,
                durationListened: TimeInterval(i * 10)
            ))
        }

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )

        #expect(data.topTracks.count == 10)
        #expect(data.topTracks[0].rank == 1)
        #expect(data.topTracks[0].trackId == "t15")   // longest
        #expect(data.topTracks[9].rank == 10)
        #expect(data.topTracks[9].trackId == "t6")    // 10th longest (t15..t6)
        // ranks are 1-10 consecutively
        #expect(data.topTracks.map(\.rank) == Array(1...10))
    }

    // e) Duration tie: deterministic by trackId ascending
    @Test func topTracks_durationTie_sortedByTrackIdAscending() async throws {
        let service = try makeService()
        let ts = utcDate(year: 2026, month: 3, day: 1)
        for id in ["tz", "ta", "tm"] {
            await service.recordPlayback(makeDTO(
                trackId: id, trackTitle: id,
                timestamp: ts, durationListened: 200
            ))
        }

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )

        #expect(data.topTracks.count == 3)
        #expect(data.topTracks[0].trackId == "ta")
        #expect(data.topTracks[1].trackId == "tm")
        #expect(data.topTracks[2].trackId == "tz")
    }

    // f) dominantGenre: correct genre, tie → alphabetical
    @Test func dominantGenre_picksHighestDuration() async throws {
        let service = try makeService()
        let ts = utcDate(year: 2026, month: 3, day: 1)
        await service.recordPlayback(makeDTO(genre: "Rock", timestamp: ts, durationListened: 300))
        await service.recordPlayback(makeDTO(trackId: "t2", genre: "Jazz",
            timestamp: Calendar.current.date(byAdding: .hour, value: 1, to: ts)!, durationListened: 100))
        await service.recordPlayback(makeDTO(trackId: "t3", genre: "Pop",
            timestamp: Calendar.current.date(byAdding: .hour, value: 2, to: ts)!, durationListened: 200))

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )
        #expect(data.dominantGenre == "Rock")
    }

    @Test func dominantGenre_perfectTie_alphabeticalWins() async throws {
        let service = try makeService()
        let ts = utcDate(year: 2026, month: 3, day: 1)
        await service.recordPlayback(makeDTO(genre: "Rock", timestamp: ts, durationListened: 200))
        await service.recordPlayback(makeDTO(trackId: "t2", genre: "Jazz",
            timestamp: Calendar.current.date(byAdding: .hour, value: 1, to: ts)!, durationListened: 200))

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )
        // Tie: Jazz < Rock alphabetically, so Jazz wins
        #expect(data.dominantGenre == "Jazz")
    }

    // g) dominantGenre: all events have no genre → nil
    @Test func dominantGenre_noGenreEvents_returnsNil() async throws {
        let service = try makeService()
        let ts = utcDate(year: 2026, month: 3, day: 1)
        await service.recordPlayback(makeDTO(genre: nil, timestamp: ts))

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )
        #expect(data.dominantGenre == nil)
    }

    // l) firstTrack / lastTrack: chronological order
    @Test func firstAndLastTrack_chronologicalOrder() async throws {
        let service = try makeService()
        let t1 = utcDate(year: 2026, month: 3, day: 1, hour: 8)
        let t2 = utcDate(year: 2026, month: 3, day: 15, hour: 10)
        let t3 = utcDate(year: 2026, month: 3, day: 28, hour: 22)

        await service.recordPlayback(makeDTO(trackId: "mid", trackTitle: "Mid", timestamp: t2, durationListened: 100))
        await service.recordPlayback(makeDTO(trackId: "last", trackTitle: "Last", timestamp: t3, durationListened: 120))
        await service.recordPlayback(makeDTO(trackId: "first", trackTitle: "First", timestamp: t1, durationListened: 80))

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )

        #expect(data.firstTrackOfPeriod?.trackId == "first")
        #expect(data.firstTrackOfPeriod?.totalSecondsListened == 80)
        #expect(data.lastTrackOfPeriod?.trackId == "last")
        #expect(data.lastTrackOfPeriod?.totalSecondsListened == 120)
        #expect(data.firstTrackOfPeriod?.rank == 0)
        #expect(data.lastTrackOfPeriod?.rank == 0)
    }

    // m) Period filtering: events outside period are ignored
    @Test func periodFiltering_eventsOutsidePeriodIgnored() async throws {
        let service = try makeService()
        let inPeriod = utcDate(year: 2026, month: 3, day: 15)
        let beforePeriod = utcDate(year: 2026, month: 2, day: 28)
        let afterPeriod = utcDate(year: 2026, month: 4, day: 1)

        await service.recordPlayback(makeDTO(trackId: "in", timestamp: inPeriod, durationListened: 300))
        await service.recordPlayback(makeDTO(trackId: "before", timestamp: beforePeriod, durationListened: 999))
        await service.recordPlayback(makeDTO(trackId: "after", timestamp: afterPeriod, durationListened: 999))

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )

        #expect(data.totalTracksPlayed == 1)
        #expect(data.totalSecondsListened == 300)
        #expect(data.topTracks[0].trackId == "in")
    }

    // n) Multi-server isolation
    @Test func multiServer_eventsOfOtherServerIgnored() async throws {
        let service = try makeService()
        let ts = utcDate(year: 2026, month: 3, day: 10)
        await service.recordPlayback(makeDTO(trackId: "t1", timestamp: ts, durationListened: 200, serverId: "srv-A"))
        await service.recordPlayback(makeDTO(trackId: "t2", timestamp: ts, durationListened: 500, serverId: "srv-B"))

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv-A", calendar: utcCalendar
        )

        #expect(data.totalTracksPlayed == 1)
        #expect(data.topTracks[0].trackId == "t1")
    }

    // o) Albums with nil albumId excluded from topAlbums but count in totalSecondsListened
    @Test func nilAlbumId_excludedFromTopAlbums_countedInTotal() async throws {
        let service = try makeService()
        let ts = utcDate(year: 2026, month: 3, day: 10)
        await service.recordPlayback(makeDTO(albumId: nil, albumTitle: nil, timestamp: ts, durationListened: 400))
        await service.recordPlayback(makeDTO(trackId: "t2", albumId: "alb2", albumTitle: "Album 2",
            timestamp: Calendar.current.date(byAdding: .hour, value: 1, to: ts)!, durationListened: 100))

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )

        #expect(data.totalSecondsListened == 500)
        #expect(data.totalTracksPlayed == 2)
        #expect(data.topAlbums.count == 1)
        #expect(data.topAlbums[0].albumId == "alb2")
    }

    // p) Artists with nil artistId excluded from topArtists but count in total
    @Test func nilArtistId_excludedFromTopArtists_countedInTotal() async throws {
        let service = try makeService()
        let ts = utcDate(year: 2026, month: 3, day: 10)
        await service.recordPlayback(makeDTO(artistId: nil, timestamp: ts, durationListened: 400))
        await service.recordPlayback(makeDTO(trackId: "t2", artistId: "a2", artistName: "Artist 2",
            timestamp: Calendar.current.date(byAdding: .hour, value: 1, to: ts)!, durationListened: 100))

        let data = await service.wrappedData(
            for: .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )

        #expect(data.totalSecondsListened == 500)
        #expect(data.totalUniqueArtists == 1)
        #expect(data.topArtists.count == 1)
        #expect(data.topArtists[0].artistId == "a2")
    }

    // hasEventsInPeriod
    @Test func hasEventsInPeriod_noEvents_returnsFalse() async throws {
        let service = try makeService()
        let result = await service.hasEventsInPeriod(
            .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )
        #expect(result == false)
    }

    @Test func hasEventsInPeriod_eventInPeriod_returnsTrue() async throws {
        let service = try makeService()
        await service.recordPlayback(makeDTO(timestamp: utcDate(year: 2026, month: 3, day: 15)))
        let result = await service.hasEventsInPeriod(
            .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )
        #expect(result == true)
    }

    @Test func hasEventsInPeriod_eventOutsidePeriod_returnsFalse() async throws {
        let service = try makeService()
        await service.recordPlayback(makeDTO(timestamp: utcDate(year: 2026, month: 2, day: 15)))
        let result = await service.hasEventsInPeriod(
            .month(year: 2026, month: 3), serverId: "srv", calendar: utcCalendar
        )
        #expect(result == false)
    }
}
