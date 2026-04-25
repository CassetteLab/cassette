// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

nonisolated enum PinError: Error, LocalizedError {
    case limitReached

    var errorDescription: String? {
        switch self {
        case .limitReached: "Maximum 6 items can be pinned to Home."
        }
    }
}

@MainActor
protocol PinServiceProtocol: AnyObject {
    func pin(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String,
        coverArtId: String?,
        serverId: UUID
    ) throws
    func unpin(itemType: PinnedItemType, itemId: String)
    func isPinned(itemType: PinnedItemType, itemId: String) -> Bool
    func reorder(items: [PinnedItem])
    func currentPinnedCount() -> Int
}
