// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

/// Snapshot of the play queue persisted on app background for restoration on next launch.
/// TODO(v1.x): extend with bidirectional server sync via savePlayQueue / getPlayQueue.
@Model
final class QueueSnapshot {
    var id: UUID
    var serverId: UUID
    var songIds: [String]       // ordered list of Subsonic song IDs
    var currentIndex: Int
    var positionSeconds: Double
    var savedAt: Date

    init(
        id: UUID = UUID(),
        serverId: UUID,
        songIds: [String],
        currentIndex: Int,
        positionSeconds: Double,
        savedAt: Date = Date()
    ) {
        self.id = id
        self.serverId = serverId
        self.songIds = songIds
        self.currentIndex = currentIndex
        self.positionSeconds = positionSeconds
        self.savedAt = savedAt
    }
}
