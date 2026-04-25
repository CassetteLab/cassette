// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

nonisolated enum FavoriteType: String, CaseIterable, Sendable {
    case song
    case album
    case artist
}

/// Local cache of server-side starred items. Synced from getStarred2 on launch
/// and updated optimistically on star/unstar actions.
@Model
final class FavoriteRecord {
    @Attribute(.unique) var id: String  // "{type}:{itemId}", e.g. "song:abc123"
    var itemType: String
    var itemId: String
    var starredDate: Date
    var serverId: UUID

    init(itemType: FavoriteType, itemId: String, starredDate: Date, serverId: UUID) {
        self.itemType = itemType.rawValue
        self.itemId = itemId
        self.id = "\(itemType.rawValue):\(itemId)"
        self.starredDate = starredDate
        self.serverId = serverId
    }
}
