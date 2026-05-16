// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

@Model
final class DownloadedAlbum {
    var id: UUID
    var albumId: String
    var serverId: UUID
    var name: String
    var artist: String?
    /// Number of tracks successfully written to disk (may be less than totalTracksCount if some failed).
    var tracksCount: Int
    /// Total tracks in the album at the time of download request.
    var totalTracksCount: Int
    var downloadedAt: Date
    var coverArtId: String?
    /// Relative path (from Documents/app.cassette/) to the cached cover art file. Nil if not downloaded.
    var localCoverArtPath: String?

    /// True when every track was successfully downloaded.
    var isComplete: Bool { tracksCount == totalTracksCount }

    init(
        id: UUID = UUID(),
        albumId: String,
        serverId: UUID,
        name: String,
        artist: String? = nil,
        tracksCount: Int,
        totalTracksCount: Int,
        downloadedAt: Date = Date(),
        coverArtId: String? = nil,
        localCoverArtPath: String? = nil
    ) {
        self.id = id
        self.albumId = albumId
        self.serverId = serverId
        self.name = name
        self.artist = artist
        self.tracksCount = tracksCount
        self.totalTracksCount = totalTracksCount
        self.downloadedAt = downloadedAt
        self.coverArtId = coverArtId
        self.localCoverArtPath = localCoverArtPath
    }
}
