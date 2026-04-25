// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
    var album: String?
    var trackNumber: Int?
    var durationSeconds: Int?
    var coverArtId: String?
    var suffix: String?

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
        album: String? = nil,
        trackNumber: Int? = nil,
        durationSeconds: Int? = nil,
        coverArtId: String? = nil,
        suffix: String? = nil
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
        self.album = album
        self.trackNumber = trackNumber
        self.durationSeconds = durationSeconds
        self.coverArtId = coverArtId
        self.suffix = suffix
    }
}
