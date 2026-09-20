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
