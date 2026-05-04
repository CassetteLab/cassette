// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
    let albumId: String? = nil
    let albumName: String?
    let artistId: String? = nil
    let genre: String? = nil
    let duration: TimeInterval
    let trackNumber: Int?
    let isDownloaded: Bool
    let coverArtId: String?
    let audioFormat: String?
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
    }

    @MainActor
    init(from track: DownloadedTrack) {
        self.id = track.songId
        self.title = track.title
        self.artist = track.artist
        self.albumId = track.albumId
        self.albumName = track.album
        self.artistId = nil
        self.genre = nil
        self.duration = track.durationSeconds.map(TimeInterval.init) ?? 0
        self.trackNumber = track.trackNumber
        self.isDownloaded = true
        self.coverArtId = track.coverArtId
        self.audioFormat = track.suffix?.uppercased()
    }
}
