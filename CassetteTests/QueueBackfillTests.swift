// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("Queue backfill — pure selection logic")
struct QueueBackfillTests {

    private func song(_ id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: "Track \(id)", artist: nil, albumId: nil, albumName: nil,
            artistId: nil, genre: nil, duration: 180, trackNumber: nil,
            isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private func event(track: String, artist: String?, genre: String?, secondsAgo: TimeInterval) -> PlaybackEventDTO {
        PlaybackEventDTO(
            trackId: track, trackTitle: "T", albumId: nil, albumTitle: nil,
            artistId: artist, artistName: artist ?? "", genre: genre,
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000_000 - secondsAgo),
            durationListened: 60, trackDuration: 180, wasCompleted: true,
            serverId: "server"
        )
    }

    // MARK: - similaritySeeds

    @Test("seeds are distinct, newest first, and capped")
    func seedsDistinctAndCapped() {
        let events = [
            event(track: "1", artist: "a1", genre: "Rock", secondsAgo: 0),
            event(track: "2", artist: "a1", genre: "Rock", secondsAgo: 10),
            event(track: "3", artist: "a2", genre: "Jazz", secondsAgo: 20),
            event(track: "4", artist: "a3", genre: "Pop", secondsAgo: 30),
            event(track: "5", artist: "a4", genre: "Metal", secondsAgo: 40),
        ]
        let seeds = LibraryService.similaritySeeds(from: events, maxArtists: 3, maxGenres: 2)
        #expect(seeds.artistIds == ["a1", "a2", "a3"])
        #expect(seeds.genres == ["Rock", "Jazz"])
    }

    @Test("nil and empty artist/genre values are skipped")
    func seedsSkipNilAndEmpty() {
        let events = [
            event(track: "1", artist: nil, genre: nil, secondsAgo: 0),
            event(track: "2", artist: "", genre: "", secondsAgo: 10),
            event(track: "3", artist: "a1", genre: "Rock", secondsAgo: 20),
        ]
        let seeds = LibraryService.similaritySeeds(from: events)
        #expect(seeds.artistIds == ["a1"])
        #expect(seeds.genres == ["Rock"])
    }

    @Test("empty history yields empty seeds (caller degrades to pure random)")
    func emptyHistoryEmptySeeds() {
        let seeds = LibraryService.similaritySeeds(from: [])
        #expect(seeds.artistIds.isEmpty)
        #expect(seeds.genres.isEmpty)
    }

    // MARK: - assembleBackfill

    @Test("excluded ids (current queue + recent plays) never appear in the result")
    func dedupesAgainstExcluded() {
        let pool = (1...20).map { song("\($0)") }
        let excluded: Set<String> = ["1", "2", "3", "10"]
        let result = LibraryService.assembleBackfill(pool: pool, excludedIds: excluded, targetSize: 50)
        #expect(result.count == 16)
        #expect(!result.contains { excluded.contains($0.id) })
    }

    @Test("duplicate pool entries (artist ∩ genre overlap) appear only once")
    func dedupesWithinPool() {
        let pool = (1...10).map { song("\($0)") } + (1...10).map { song("\($0)") }
        let result = LibraryService.assembleBackfill(pool: pool, excludedIds: [], targetSize: 50)
        #expect(result.count == 10)
        #expect(Set(result.map(\.id)).count == 10)
    }

    @Test("result is capped at targetSize")
    func capsAtTargetSize() {
        let pool = (1...200).map { song("\($0)") }
        let result = LibraryService.assembleBackfill(pool: pool, excludedIds: [], targetSize: 50)
        #expect(result.count == 50)
        #expect(Set(result.map(\.id)).count == 50)
    }

    @Test("empty pool returns empty (caller tops up with random fill)")
    func emptyPoolReturnsEmpty() {
        let result = LibraryService.assembleBackfill(pool: [], excludedIds: ["1"], targetSize: 50)
        #expect(result.isEmpty)
    }

    @Test("thin pool returns everything available, leaving the remainder to random fill")
    func thinPoolReturnsAllAvailable() {
        let pool = (1...7).map { song("\($0)") }
        let result = LibraryService.assembleBackfill(pool: pool, excludedIds: ["7"], targetSize: 50)
        #expect(result.count == 6)
        // The caller's top-up pass excludes already-selected ids the same way:
        let topUp = LibraryService.assembleBackfill(
            pool: (1...60).map { song("r\($0)") },
            excludedIds: Set(result.map(\.id)).union(["7"]),
            targetSize: 50 - result.count
        )
        #expect(topUp.count == 44)
        #expect(Set(topUp.map(\.id)).isDisjoint(with: Set(result.map(\.id))))
    }
}
