// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

@Model
final class DownloadedTrack {
    var id: UUID
    var songId: String
    var serverId: UUID
    var albumId: String?
    var filePath: String        // relative to Documents/app.cassette/downloads/
    var fileSize: Int64
    var mimeType: String
    var downloadedAt: Date
    // Denormalized metadata for offline display (no network required in offline mode)
    var title: String
    var artist: String?
    var artistId: String?
    var album: String?
    var trackNumber: Int?
    var durationSeconds: Int?
    var coverArtId: String?
    var suffix: String?
    var genre: String?
    // ReplayGain metadata — captured at download time for offline normalization.
    var replayGainTrackGain: Double?
    var replayGainTrackPeak: Double?
    var replayGainAlbumGain: Double?
    var replayGainAlbumPeak: Double?
    var replayGainBaseGain: Double?
    var replayGainFallbackGain: Double?

    init(
        id: UUID = UUID(),
        songId: String,
        serverId: UUID,
        albumId: String? = nil,
        filePath: String,
        fileSize: Int64,
        mimeType: String,
        downloadedAt: Date = Date(),
        title: String,
        artist: String? = nil,
        artistId: String? = nil,
        album: String? = nil,
        trackNumber: Int? = nil,
        durationSeconds: Int? = nil,
        coverArtId: String? = nil,
        suffix: String? = nil,
        genre: String? = nil,
        replayGainTrackGain: Double? = nil,
        replayGainTrackPeak: Double? = nil,
        replayGainAlbumGain: Double? = nil,
        replayGainAlbumPeak: Double? = nil,
        replayGainBaseGain: Double? = nil,
        replayGainFallbackGain: Double? = nil
    ) {
        self.id = id
        self.songId = songId
        self.serverId = serverId
        self.albumId = albumId
        self.filePath = filePath
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.downloadedAt = downloadedAt
        self.title = title
        self.artist = artist
        self.artistId = artistId
        self.album = album
        self.trackNumber = trackNumber
        self.durationSeconds = durationSeconds
        self.coverArtId = coverArtId
        self.suffix = suffix
        self.genre = genre
        self.replayGainTrackGain = replayGainTrackGain
        self.replayGainTrackPeak = replayGainTrackPeak
        self.replayGainAlbumGain = replayGainAlbumGain
        self.replayGainAlbumPeak = replayGainAlbumPeak
        self.replayGainBaseGain = replayGainBaseGain
        self.replayGainFallbackGain = replayGainFallbackGain
    }
}
