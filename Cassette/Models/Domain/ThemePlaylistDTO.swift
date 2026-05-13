// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Safe cross-actor representation of a ThemePlaylistRecord.
nonisolated struct ThemePlaylistDTO: Sendable, Identifiable, Hashable {
    let serverId: String
    let type: ThemePlaylistType
    let playlistId: String
    let title: String
    let trackIds: [String]
    let lastSyncedAt: Date

    var id: String { playlistId }
    var trackCount: Int { trackIds.count }
}
