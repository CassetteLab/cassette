// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

/// Library stub answering only the two calls the tag provider makes.
private final class TagLibraryStub: LibraryServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _genreQueries: [String] = []
    private var _randomCalls = 0

    /// Songs returned per genre. Absent genres return empty, like a real server.
    var songsPerGenre: [String: [Song]] = [:]
    var randomPool: [Song] = []

    var genreQueries: [String] { lock.withLock { _genreQueries } }
    var randomCalls: Int { lock.withLock { _randomCalls } }

    func songsByGenre(_ genre: String, count: Int) async throws -> [Song] {
        lock.withLock { _genreQueries.append(genre) }
        return songsPerGenre[genre] ?? []
    }

    func randomSongs(size: Int) async throws -> [Song] {
        lock.withLock { _randomCalls += 1 }
        return randomPool
    }

    // Unused by the provider.
    func search(_ query: String) async throws -> SearchResult3 { throw URLError(.unknown) }
    func artists() async throws -> [ArtistIndex] { throw URLError(.unknown) }
    func artist(id: String) async throws -> ArtistID3 { throw URLError(.unknown) }
    func album(id: String) async throws -> AlbumID3 { throw URLError(.unknown) }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { [] }
    func playlists() async throws -> [Playlist] { [] }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    func coverArtURL(id: String, size: Int?) async -> URL? { nil }
    func streamURL(songId: String) async -> URL? { nil }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {}
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {}
    func getStarred2() async throws -> Starred2 { throw URLError(.unknown) }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { [] }
    func allAlbums() async throws -> [AlbumID3] { [] }
    func allSongs(offset: Int, count: Int) async throws -> [Song] { [] }
    func scrobble(songId: String, submission: Bool) async {}
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { [] }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { [] }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { [] }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { [] }
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {}
    func getPlayQueue() async throws -> SavedPlayQueue? { nil }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw URLError(.unknown) }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }
    func findArtist(byName name: String) async -> ArtistID3? { nil }
    func topSongs(artist: String, count: Int) async throws -> [DisplayableSong] { [] }
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong] { [] }
}

/// Song is Decodable-only, so fixtures are built from JSON.
private func song(id: String, genre: String? = nil, bpm: Int? = nil, moods: [String] = []) throws -> Song {
    var fields: [String] = [#""id":"\#(id)""#, #""title":"T""#, #""isDir":false"#]
    if let genre { fields.append(#""genre":"\#(genre)""#) }
    if let bpm { fields.append(#""bpm":\#(bpm)"#) }
    if !moods.isEmpty {
        fields.append(#""moods":[\#(moods.map { #""\#($0)""# }.joined(separator: ","))]"#)
    }
    return try JSONDecoder().decode(Song.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
}

@Suite("Mood playlists — tag provider candidate sourcing")
struct LibraryTagTrackProviderTests {

    @Test("genres present in the library are used directly")
    func genresAreUsedWhenPresent() async throws {
        let library = TagLibraryStub()
        library.songsPerGenre["dance"] = [try song(id: "a", genre: "Dance", bpm: 130)]
        let provider = LibraryTagTrackProvider(libraryService: library)

        let ids = try await provider.trackIds(for: .energetic, limit: 10)

        #expect(ids == ["a"])
        #expect(library.randomCalls == 0, "no need for the broad pool when genres answered")
    }

    @Test("a library with none of a mood's genres falls back to a broad sample")
    func emptyGenresFallBackToRandomPool() async throws {
        // The case a real library hit: French rap, so Night's ambient/jazz/classical genres are all
        // absent and every genre query comes back empty. Before the fallback this produced nothing
        // at all, every week, forever.
        let library = TagLibraryStub()
        library.randomPool = [
            try song(id: "slow", bpm: 70),
            try song(id: "fast", bpm: 175),
        ]
        let provider = LibraryTagTrackProvider(libraryService: library)

        let ids = try await provider.trackIds(for: .night, limit: 10)

        #expect(library.randomCalls == 1)
        #expect(ids == ["slow"], "BPM alone should still separate a night track from a fast one")
    }

    @Test("the broad sample uses MOOD tags when there is no BPM")
    func fallbackUsesMoodTags() async throws {
        let library = TagLibraryStub()
        library.randomPool = [
            try song(id: "calm", moods: ["Calm"]),
            try song(id: "angry", moods: ["Aggressive"]),
        ]
        let provider = LibraryTagTrackProvider(libraryService: library)

        #expect(try await provider.trackIds(for: .night, limit: 10) == ["calm"])
        #expect(try await provider.trackIds(for: .workout, limit: 10) == ["angry"])
    }

    @Test("an untagged library yields nothing rather than something arbitrary")
    func untaggedLibraryYieldsNothing() async throws {
        let library = TagLibraryStub()
        library.randomPool = [try song(id: "a"), try song(id: "b")]
        let provider = LibraryTagTrackProvider(libraryService: library)

        // Empty is the correct answer: the sync treats it as a skip and leaves the previous
        // playlist untouched, rather than filling it with music chosen at random.
        #expect(try await provider.trackIds(for: .chill, limit: 10).isEmpty)
    }

    @Test("every one of a mood's genres is queried")
    func allGenresAreQueried() async throws {
        let library = TagLibraryStub()
        let provider = LibraryTagTrackProvider(libraryService: library)

        _ = try await provider.trackIds(for: .workout, limit: 10)

        #expect(library.genreQueries == MoodTagMatcher.genres(.workout))
    }

    @Test("a track appearing under two of a mood's genres is only counted once")
    func duplicatesAreDeduped() async throws {
        let library = TagLibraryStub()
        let shared = try song(id: "dup", genre: "Ambient", bpm: 80)
        library.songsPerGenre["ambient"] = [shared]
        library.songsPerGenre["classical"] = [shared]
        let provider = LibraryTagTrackProvider(libraryService: library)

        #expect(try await provider.trackIds(for: .night, limit: 10) == ["dup"])
    }
}
