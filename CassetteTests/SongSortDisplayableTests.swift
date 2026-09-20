// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

/// The display-model sorting path used by playlist detail. The playlist sort is display-only,
/// so what matters is that it orders what is shown without ever becoming the playlist's order.
@Suite("SongSort — display-model path")
struct SongSortDisplayableTests {

    private func song(_ id: String, title: String, artist: String? = nil) -> DisplayableSong {
        DisplayableSong(
            id: id, title: title, artist: artist, albumId: nil, albumName: nil,
            artistId: nil, genre: nil, duration: 180, trackNumber: nil,
            isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private var unordered: [DisplayableSong] {
        [song("c", title: "Cinder", artist: "Zephyr"),
         song("a", title: "Aurora", artist: "Marrow"),
         song("b", title: "Bramble", artist: "Aster")]
    }

    @Test("title orders by title")
    func byTitle() {
        #expect(SongSort.title.sorted(unordered).map(\.id) == ["a", "b", "c"])
    }

    @Test("artist orders by artist, then title")
    func byArtist() {
        #expect(SongSort.artist.sorted(unordered).map(\.id) == ["b", "a", "c"])
    }

    @Test("recentlyAdded uses the server metadata it is given")
    func byRecentlyAdded() {
        let meta: [String: Song] = [
            "a": Song(id: "a", title: "Aurora", created: Date(timeIntervalSince1970: 100)),
            "b": Song(id: "b", title: "Bramble", created: Date(timeIntervalSince1970: 300)),
            "c": Song(id: "c", title: "Cinder", created: Date(timeIntervalSince1970: 200)),
        ]
        #expect(SongSort.recentlyAdded.sorted(unordered, metadata: meta).map(\.id) == ["b", "c", "a"])
    }

    @Test("songs with no metadata sort last rather than scrambling the list")
    func missingMetadataSortsLast() {
        let meta: [String: Song] = [
            "b": Song(id: "b", title: "Bramble", created: Date(timeIntervalSince1970: 300)),
        ]
        #expect(SongSort.recentlyAdded.sorted(unordered, metadata: meta).first?.id == "b")
    }

    @Test("offline drops the two orderings DownloadedTrack cannot support")
    func offlineOptions() {
        let offline = SongSort.available(hasServerMetadata: false)
        #expect(offline == [.title, .artist])
        #expect(!offline.contains(.recentlyAdded))
        #expect(!offline.contains(.releaseDate))
        #expect(SongSort.available(hasServerMetadata: true).count == SongSort.allCases.count)
    }

    @Test("sorting is a view of the list, never a reordering of it")
    func sortDoesNotMutateInput() {
        let original = unordered
        _ = SongSort.title.sorted(original)
        #expect(original.map(\.id) == ["c", "a", "b"])
    }
}

/// The display sort must never leak into an operation expressed against the playlist's own
/// order. Two paths did: `removeTrack` sent a displayed position to a server-side index, and
/// Add Music sent the displayed order into an atomic full-list replace.
@Suite("Playlist sort — display order never becomes playlist order")
@MainActor
struct PlaylistSortOrderingTests {

    private func song(_ id: String, _ title: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: title, artist: nil, albumId: nil, albumName: nil,
            artistId: nil, genre: nil, duration: 1, trackNumber: nil,
            isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    /// Playlist order is deliberately not alphabetical, so a title sort reorders it.
    private var playlistOrder: [DisplayableSong] {
        [song("s3", "Cinder"), song("s1", "Aurora"), song("s2", "Bramble")]
    }

    @Test("a title sort changes what is shown")
    func sortReorders() {
        #expect(playlistOrder.map(\.id) == ["s3", "s1", "s2"])
        #expect(SongSort.title.sorted(playlistOrder).map(\.id) == ["s1", "s2", "s3"])
    }

    @Test("a displayed position is not a playlist position once sorted")
    func displayedIndexIsNotPlaylistIndex() {
        let sorted = SongSort.title.sorted(playlistOrder)
        // Row 0 of the sorted list is "Aurora", which sits at playlist position 1.
        let displayedIndex = 0
        let songAtRow = sorted[displayedIndex]
        let playlistIndex = playlistOrder.firstIndex { $0.id == songAtRow.id }
        #expect(playlistIndex == 1)
        #expect(playlistIndex != displayedIndex, "this is exactly what removeTrack had to translate")
    }

    @Test("the list Add Music replaces is the playlist order, not the sorted one")
    func addMusicSendsPlaylistOrder() {
        let sorted = SongSort.title.sorted(playlistOrder)
        let added = song("s4", "Dusk")

        // What the bug did: append to the DISPLAYED order and replace the playlist with it.
        let wrong = sorted.map(\.id) + [added.id]
        #expect(wrong == ["s1", "s2", "s3", "s4"], "would have rewritten the playlist alphabetically")

        // What it does now: append to the playlist's own order.
        let right = playlistOrder.map(\.id) + [added.id]
        #expect(right == ["s3", "s1", "s2", "s4"], "playlist order preserved, new track appended")
        #expect(right != wrong)
    }
}
