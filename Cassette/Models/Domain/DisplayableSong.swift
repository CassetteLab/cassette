// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

/// Unified song model for display and playback in Cassette.
///
/// Constructed from either a SwiftSonic `Song` (online) or a `DownloadedTrack` (offline).
/// PlayerService, SongRow, and all detail ViewModels work exclusively with this type —
/// SwiftSonic types are DTOs consumed at the API boundary only.
nonisolated struct DisplayableSong: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let artist: String?
    let albumId: String?
    let albumName: String?
    let artistId: String?
    let genre: String?
    let duration: TimeInterval
    let trackNumber: Int?
    var isDownloaded: Bool
    let coverArtId: String?
    let audioFormat: String?
    let replayGainTrackGain: Double?
    let replayGainTrackPeak: Double?
    let replayGainAlbumGain: Double?
    let replayGainAlbumPeak: Double?
    /// OpenSubsonic: always added to the selected mode's gain when present.
    let replayGainBaseGain: Double?
    /// OpenSubsonic: used as fallback when the selected mode's gain is absent.
    let replayGainFallbackGain: Double?
}

extension DisplayableSong {
    nonisolated init(from song: Song, isDownloaded: Bool = false) {
        self.id = song.id
        self.title = song.title
        self.artist = song.artist
        self.albumId = song.albumId
        self.albumName = song.album
        self.artistId = song.artistId
        self.genre = song.genres?.first?.name ?? song.genre
        self.duration = song.duration.map(TimeInterval.init) ?? 0
        self.trackNumber = song.track
        self.isDownloaded = isDownloaded
        self.coverArtId = song.coverArt
        self.audioFormat = song.suffix?.uppercased()
        self.replayGainTrackGain = song.replayGain?.trackGain
        self.replayGainTrackPeak = song.replayGain?.trackPeak
        self.replayGainAlbumGain = song.replayGain?.albumGain
        self.replayGainAlbumPeak = song.replayGain?.albumPeak
        self.replayGainBaseGain = song.replayGain?.baseGain
        self.replayGainFallbackGain = song.replayGain?.fallbackGain
    }

    @MainActor
    init(from track: DownloadedTrack) {
        self.id = track.songId
        self.title = track.title
        self.artist = track.artist
        self.albumId = track.albumId
        self.albumName = track.album
        self.artistId = track.artistId
        self.genre = track.genre
        self.duration = track.durationSeconds.map(TimeInterval.init) ?? 0
        self.trackNumber = track.trackNumber
        self.isDownloaded = true
        self.coverArtId = track.coverArtId
        self.audioFormat = track.suffix?.uppercased()
        self.replayGainTrackGain = track.replayGainTrackGain
        self.replayGainTrackPeak = track.replayGainTrackPeak
        self.replayGainAlbumGain = track.replayGainAlbumGain
        self.replayGainAlbumPeak = track.replayGainAlbumPeak
        self.replayGainBaseGain = track.replayGainBaseGain
        self.replayGainFallbackGain = track.replayGainFallbackGain
    }

    /// A copy with `isDownloaded` flipped — the 16 fields are otherwise identical. Rebuilding it by hand (as 10
    /// sites did) risks silently dropping a newly-added optional field; this can't.
    func withDownloaded(_ flag: Bool) -> DisplayableSong {
        var copy = self
        copy.isDownloaded = flag
        return copy
    }
}
