// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

/// A single counted playback event for Wrapped statistics.
///
/// Recorded when a track ends naturally (wasCompleted=true) or is skipped
/// after at least 30 seconds (wasCompleted depends on position/duration ratio).
/// All metadata fields are snapshotted at recording time for resilience against
/// server-side deletions. PersistentModel instances never cross actor boundaries —
/// use PlaybackEventDTO for all inter-actor communication.
@Model
final class PlaybackEvent {
    var timestamp: Date
    var serverId: String

    var id: UUID
    var trackId: String
    var trackTitle: String
    var albumId: String?
    var albumTitle: String?
    var artistId: String?
    var artistName: String
    var genre: String?
    var durationListened: TimeInterval
    var trackDuration: TimeInterval
    var wasCompleted: Bool

    #Index<PlaybackEvent>([\.timestamp], [\.serverId])

    init(
        id: UUID = UUID(),
        trackId: String,
        trackTitle: String,
        albumId: String?,
        albumTitle: String?,
        artistId: String?,
        artistName: String,
        genre: String?,
        timestamp: Date = Date(),
        durationListened: TimeInterval,
        trackDuration: TimeInterval,
        wasCompleted: Bool,
        serverId: String
    ) {
        self.id = id
        self.trackId = trackId
        self.trackTitle = trackTitle
        self.albumId = albumId
        self.albumTitle = albumTitle
        self.artistId = artistId
        self.artistName = artistName
        self.genre = genre
        self.timestamp = timestamp
        self.durationListened = durationListened
        self.trackDuration = trackDuration
        self.wasCompleted = wasCompleted
        self.serverId = serverId
    }
}
