// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

@Suite("AlbumSort")
struct AlbumSortTests {

    private func album(
        _ id: String, artist: String? = nil, year: Int? = nil, genre: String? = nil,
        playCount: Int? = nil, played: Date? = nil, starred: Date? = nil, rating: Int? = nil
    ) -> AlbumID3 {
        AlbumID3(
            id: id, name: id, songCount: 10, duration: 2400, artist: artist,
            playCount: playCount, starred: starred, year: year, genre: genre,
            played: played, userRating: rating
        )
    }

    private func ids(_ sort: AlbumSort, _ albums: [AlbumID3]) -> [String] {
        sort.sorted(albums).map(\.id)
    }

    @Test("artist groups by artist, oldest release first, missing artist last")
    func byArtist() {
        let albums = [
            album("orphan"),
            album("zeta-2020", artist: "Zeta", year: 2020),
            album("aster-2015", artist: "Aster", year: 2015),
            album("zeta-2010", artist: "Zeta", year: 2010),
            album("aster-none", artist: "Aster"),
            album("aster-2005", artist: "Aster", year: 2005),
        ]
        #expect(ids(.artist, albums) == ["aster-2005", "aster-2015", "aster-none", "zeta-2010", "zeta-2020", "orphan"])
    }

    @Test("artist falls back to album name when artist and year match")
    func byArtistTieBreak() {
        let albums = [album("b", artist: "A", year: 2000), album("a", artist: "A", year: 2000)]
        #expect(ids(.artist, albums) == ["a", "b"])
    }

    @Test("most played puts the highest play count first, unplayed last")
    func byMostPlayed() {
        let albums = [album("none"), album("low", playCount: 2), album("high", playCount: 40)]
        #expect(ids(.mostPlayed, albums) == ["high", "low", "none"])
    }

    @Test("recently played puts the latest play first, never-played last")
    func byRecentlyPlayed() {
        let albums = [
            album("never"),
            album("old", played: Date(timeIntervalSince1970: 1_000)),
            album("new", played: Date(timeIntervalSince1970: 2_000)),
        ]
        #expect(ids(.recentlyPlayed, albums) == ["new", "old", "never"])
    }

    @Test("genre orders alphabetically, missing genre last")
    func byGenre() {
        let albums = [album("none"), album("rock", genre: "Rock"), album("jazz", genre: "Jazz")]
        #expect(ids(.genre, albums) == ["jazz", "rock", "none"])
    }

    @Test("starred puts the most recently starred first, unstarred last")
    func byStarred() {
        let albums = [
            album("plain"),
            album("early", starred: Date(timeIntervalSince1970: 1_000)),
            album("late", starred: Date(timeIntervalSince1970: 2_000)),
        ]
        #expect(ids(.starred, albums) == ["late", "early", "plain"])
    }

    @Test("rating puts the best rated first, unrated last")
    func byRating() {
        let albums = [album("unrated"), album("three", rating: 3), album("five", rating: 5)]
        #expect(ids(.rating, albums) == ["five", "three", "unrated"])
    }

    @Test("every option has a label and an icon")
    func labelsAndIcons() {
        for sort in AlbumSort.allCases {
            #expect(!sort.label.isEmpty)
            #expect(!sort.systemImage.isEmpty)
        }
    }

    @Test("the jump bar files albums under their artist's initial")
    func artistJumpBarKey() {
        let albums = [album("a", artist: "Marrow"), album("b", artist: "3 Doors Down")]
        #expect(albums.availableAlphabetLetters(keyPath: \.artistOrEmpty) == ["M", "#"])
    }
}

@Suite("ArtistSort")
struct ArtistSortTests {

    private func artist(_ id: String, starred: Date? = nil, rating: Int? = nil) -> ArtistID3 {
        ArtistID3(id: id, name: id, starred: starred, userRating: rating)
    }

    @Test("starred puts the most recently starred first, unstarred by name")
    func byStarred() {
        let artists = [
            artist("b"), artist("a"),
            artist("early", starred: Date(timeIntervalSince1970: 1_000)),
            artist("late", starred: Date(timeIntervalSince1970: 2_000)),
        ]
        #expect(ArtistSort.starred.sorted(artists).map(\.id) == ["late", "early", "a", "b"])
    }

    @Test("rating puts the best rated first, unrated by name")
    func byRating() {
        let artists = [artist("b"), artist("a"), artist("five", rating: 5), artist("three", rating: 3)]
        #expect(ArtistSort.rating.sorted(artists).map(\.id) == ["five", "three", "a", "b"])
    }
}


// MARK: - A–Z jump bar

@Suite("AlbumSort jump bar")
struct AlbumSortJumpBarTests {

    private func album(_ id: String, name: String? = nil, sortName: String? = nil, artist: String? = nil) -> AlbumID3 {
        AlbumID3(id: id, name: name ?? id, songCount: 10, duration: 2400, artist: artist, sortName: sortName)
    }

    @Test("a name-ordered list is addressed by the key it is sorted by, not by the raw name")
    func nameUsesTheSortName() {
        #expect(AlbumSort.name.alphabetKeyPath == \AlbumID3.alphabetSortKey)
        // The server drops the article: "The Bends" sorts under B, so the bar must file it there.
        let albums = [album("1", name: "The Bends", sortName: "Bends")]
        #expect(albums.availableAlphabetLetters(keyPath: \.alphabetSortKey) == ["B"])
    }

    @Test("without a sort name the album name is used")
    func nameFallsBackToName() {
        #expect(album("1", name: "Kid A").alphabetSortKey == "Kid A")
    }

    @Test("an artist-ordered list is addressed by the artist")
    func artistUsesTheArtist() {
        #expect(AlbumSort.artist.alphabetKeyPath == \AlbumID3.artistOrEmpty)
    }

    @Test("orderings that are not alphabetical get no bar at all")
    func noBarForTheRest() {
        for sort in AlbumSort.allCases where sort != .name && sort != .artist {
            #expect(sort.alphabetKeyPath == nil, "\(sort) should not offer a jump bar")
        }
    }

    @Test("albums with no artist are left out of the bar, so # means one thing")
    func namelessAlbumsAreNotAddressable() {
        let albums = [
            album("marrow", artist: "Marrow"),
            album("doors", artist: "3 Doors Down"),
            album("orphan"),
        ]
        let addressable = AlbumSort.artist.alphabetAddressableAlbums(albums)
        #expect(addressable.map(\.id) == ["marrow", "doors"])
        // "#" now covers the non-letter initial at the top of the list, and nothing else.
        #expect(addressable.availableAlphabetLetters(keyPath: \.artistOrEmpty) == ["M", "#"])
    }

    @Test("a name-ordered list addresses every album")
    func nameAddressesEverything() {
        let albums = [album("a"), album("b"), album("c")]
        #expect(AlbumSort.name.alphabetAddressableAlbums(albums).count == 3)
    }
}
