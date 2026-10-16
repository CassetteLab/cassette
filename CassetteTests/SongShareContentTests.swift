// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

@Suite("SongShareContent")
struct SongShareContentTests {

    private func text(title: String, artist: String? = nil, album: String? = nil) -> String {
        let song = DisplayableSong(from: Song(id: "1", title: title, album: album, artist: artist))
        return SongShareContent(song: song).text
    }

    @Test("a song with no artist and no album shares its title alone")
    func titleOnly() {
        #expect(text(title: "Teardrop") == "♫ Teardrop")
    }

    @Test("the artist goes on a second line")
    func titleAndArtist() {
        #expect(text(title: "Teardrop", artist: "Massive Attack") == "♫ Teardrop\nMassive Attack")
    }

    @Test("the album alone also goes on the second line")
    func titleAndAlbum() {
        #expect(text(title: "Teardrop", album: "Mezzanine") == "♫ Teardrop\nMezzanine")
    }

    @Test("artist and album are joined by a middle dot")
    func titleArtistAndAlbum() {
        #expect(
            text(title: "Teardrop", artist: "Massive Attack", album: "Mezzanine")
                == "♫ Teardrop\nMassive Attack · Mezzanine"
        )
    }

    @Test("a blank artist is dropped rather than leaving a dangling separator")
    func blankArtistIsDropped() {
        #expect(text(title: "Teardrop", artist: "   ", album: "Mezzanine") == "♫ Teardrop\nMezzanine")
    }

    @Test("a blank album is dropped rather than leaving a dangling separator")
    func blankAlbumIsDropped() {
        #expect(text(title: "Teardrop", artist: "Massive Attack", album: "\n ") == "♫ Teardrop\nMassive Attack")
    }

    @Test("blank on both sides falls back to the title alone")
    func blankBothFallsBackToTitle() {
        #expect(text(title: "Teardrop", artist: " ", album: "") == "♫ Teardrop")
    }

    @Test("surrounding whitespace is trimmed from what is shared")
    func whitespaceIsTrimmed() {
        #expect(text(title: "Teardrop", artist: "  Massive Attack  ") == "♫ Teardrop\nMassive Attack")
    }
}
