// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

/// Persisted record of a server-side themed playlist managed by ThemePlaylistService.
///
/// One record per (serverId, typeRaw) pair — upserted on each weekly sync.
/// PersistentModel instances never cross actor boundaries; use ThemePlaylistDTO instead.
@Model
final class ThemePlaylistRecord {
    var serverId: String
    var typeRaw: String
    var playlistId: String
    var title: String
    var trackIds: [String]
    var lastSyncedAt: Date
    var trackCount: Int

    var type: ThemePlaylistType? { ThemePlaylistType(rawValue: typeRaw) }

    init(
        serverId: String,
        type: ThemePlaylistType,
        playlistId: String,
        title: String,
        trackIds: [String],
        lastSyncedAt: Date = Date()
    ) {
        self.serverId = serverId
        self.typeRaw = type.rawValue
        self.playlistId = playlistId
        self.title = title
        self.trackIds = trackIds
        self.lastSyncedAt = lastSyncedAt
        self.trackCount = trackIds.count
    }
}
