// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

nonisolated enum PinnedItemType: String, CaseIterable, Sendable {
    case album
    case playlist
}

/// Persists an item pinned to HomeView. Stores a metadata snapshot so the
/// pinned grid renders immediately at launch without a network round-trip.
@Model
final class PinnedItem {
    @Attribute(.unique) var id: String  // "{type}:{itemId}", e.g. "album:abc123"
    var itemType: String
    var itemId: String
    var pinnedDate: Date
    var sortOrder: Int
    var serverId: UUID
    var displayName: String
    var displaySubtitle: String
    var coverArtId: String?

    init(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String,
        coverArtId: String?,
        serverId: UUID,
        sortOrder: Int
    ) {
        self.itemType = itemType.rawValue
        self.itemId = itemId
        self.id = "\(itemType.rawValue):\(itemId)"
        self.displayName = displayName
        self.displaySubtitle = displaySubtitle
        self.coverArtId = coverArtId
        self.serverId = serverId
        self.sortOrder = sortOrder
        self.pinnedDate = Date()
    }
}
