// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("LocalCopyState")
struct LocalCopyStateTests {

    private func song(_ id: String, downloaded: Bool) -> DisplayableSong {
        DisplayableSong(
            id: id, title: id, artist: nil, albumId: nil, albumName: nil, artistId: nil,
            genre: nil, duration: 180, trackNumber: nil, isDownloaded: downloaded,
            coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    @Test("an empty collection has nothing to download")
    func empty() {
        #expect(LocalCopyState(songs: []) == .none)
    }

    @Test("no downloaded track reads as nothing downloaded")
    func nothingDownloaded() {
        #expect(LocalCopyState(songs: [song("a", downloaded: false), song("b", downloaded: false)]) == .none)
    }

    @Test("one downloaded track out of three is partial, not downloaded")
    func partial() {
        let songs = [song("a", downloaded: true), song("b", downloaded: false), song("c", downloaded: false)]
        #expect(LocalCopyState(songs: songs) == .partial(downloaded: 1, total: 3))
    }

    @Test("every track downloaded is complete")
    func complete() {
        #expect(LocalCopyState(songs: [song("a", downloaded: true), song("b", downloaded: true)]) == .complete)
    }

    @Test("a single downloaded track in a one-track collection is complete, not partial")
    func singleTrack() {
        #expect(LocalCopyState(songs: [song("a", downloaded: true)]) == .complete)
    }
}
