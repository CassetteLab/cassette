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
    let albumName: String?
    let duration: TimeInterval
    let trackNumber: Int?
    let isDownloaded: Bool
    let coverArtId: String?
    let audioFormat: String?
}

extension DisplayableSong {
    init(from song: Song, isDownloaded: Bool = false) {
        self.id = song.id
        self.title = song.title
        self.artist = song.artist
        self.albumName = song.album
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
        self.albumName = track.album
        self.duration = track.durationSeconds.map(TimeInterval.init) ?? 0
        self.trackNumber = track.trackNumber
        self.isDownloaded = true
        self.coverArtId = track.coverArtId
        self.audioFormat = track.suffix?.uppercased()
    }
}
