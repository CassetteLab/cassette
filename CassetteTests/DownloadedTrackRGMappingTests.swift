// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

@Suite("DownloadedTrack → DisplayableSong ReplayGain mapping")
@MainActor
struct DownloadedTrackRGMappingTests {

    private func makeTrack(
        trackGain: Double? = nil,
        trackPeak: Double? = nil,
        albumGain: Double? = nil,
        albumPeak: Double? = nil,
        baseGain: Double? = nil,
        fallbackGain: Double? = nil
    ) -> DownloadedTrack {
        DownloadedTrack(
            songId: "s1",
            serverId: .init(),
            filePath: "test/s1.mp3",
            fileSize: 1000,
            mimeType: "audio/mpeg",
            title: "Test Track",
            replayGainTrackGain: trackGain,
            replayGainTrackPeak: trackPeak,
            replayGainAlbumGain: albumGain,
            replayGainAlbumPeak: albumPeak,
            replayGainBaseGain: baseGain,
            replayGainFallbackGain: fallbackGain
        )
    }

    @Test("all six RG values map through to DisplayableSong")
    func allFieldsMapThrough() {
        let track = makeTrack(
            trackGain: -6.5,
            trackPeak: 0.9,
            albumGain: -5.0,
            albumPeak: 0.85,
            baseGain: 1.0,
            fallbackGain: -4.0
        )
        let song = DisplayableSong(from: track)
        #expect(song.replayGainTrackGain == -6.5)
        #expect(song.replayGainTrackPeak == 0.9)
        #expect(song.replayGainAlbumGain == -5.0)
        #expect(song.replayGainAlbumPeak == 0.85)
        #expect(song.replayGainBaseGain == 1.0)
        #expect(song.replayGainFallbackGain == -4.0)
    }

    @Test("nil RG values (pre-RG downloads) all map to nil — graceful, no crash")
    func nilFieldsRemainNil() {
        let track = makeTrack()
        let song = DisplayableSong(from: track)
        #expect(song.replayGainTrackGain == nil)
        #expect(song.replayGainTrackPeak == nil)
        #expect(song.replayGainAlbumGain == nil)
        #expect(song.replayGainAlbumPeak == nil)
        #expect(song.replayGainBaseGain == nil)
        #expect(song.replayGainFallbackGain == nil)
    }
}
