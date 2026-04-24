// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

@Model
final class DownloadedPlaylist {
    var id: UUID
    var playlistId: String
    var serverId: UUID
    var name: String
    var comment: String?
    /// Number of tracks successfully written to disk.
    var tracksCount: Int
    /// Total tracks in the playlist at the time of download request.
    var totalTracksCount: Int
    var downloadedAt: Date
    var coverArtId: String?
    /// Relative path (from Documents/app.cassette/) to the cached cover art file.
    var localCoverArtPath: String?

    var isComplete: Bool { tracksCount == totalTracksCount }

    init(
        id: UUID = UUID(),
        playlistId: String,
        serverId: UUID,
        name: String,
        comment: String? = nil,
        tracksCount: Int,
        totalTracksCount: Int,
        downloadedAt: Date = Date(),
        coverArtId: String? = nil,
        localCoverArtPath: String? = nil
    ) {
        self.id = id
        self.playlistId = playlistId
        self.serverId = serverId
        self.name = name
        self.comment = comment
        self.tracksCount = tracksCount
        self.totalTracksCount = totalTracksCount
        self.downloadedAt = downloadedAt
        self.coverArtId = coverArtId
        self.localCoverArtPath = localCoverArtPath
    }
}
