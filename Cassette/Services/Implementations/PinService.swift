// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import OSLog

@MainActor
final class PinService: PinServiceProtocol {
    private let modelContext: ModelContext
    private static let maxPinnedItems = 6

    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
    }

    // MARK: - Query

    func isPinned(itemType: PinnedItemType, itemId: String) -> Bool {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var descriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.id == compositeId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func currentPinnedCount() -> Int {
        let descriptor = FetchDescriptor<PinnedItem>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Pin

    func pin(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String,
        coverArtId: String?,
        serverId: UUID
    ) throws {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var existingDescriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.id == compositeId }
        )
        existingDescriptor.fetchLimit = 1
        if (try? modelContext.fetchCount(existingDescriptor)) ?? 0 > 0 { return }

        let count = currentPinnedCount()
        guard count < PinService.maxPinnedItems else { throw PinError.limitReached }

        let item = PinnedItem(
            itemType: itemType,
            itemId: itemId,
            displayName: displayName,
            displaySubtitle: displaySubtitle,
            coverArtId: coverArtId,
            serverId: serverId,
            sortOrder: count
        )
        modelContext.insert(item)
        try? modelContext.save()
        Logger.pin.info("Pinned \(itemType.rawValue) \(itemId) at position \(count)")
    }

    // MARK: - Unpin

    func unpin(itemType: PinnedItemType, itemId: String) {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var descriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.id == compositeId }
        )
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first else { return }

        modelContext.delete(item)

        let allDescriptor = FetchDescriptor<PinnedItem>(
            sortBy: [SortDescriptor(\PinnedItem.sortOrder)]
        )
        let remaining = (try? modelContext.fetch(allDescriptor)) ?? []
        for (index, pinned) in remaining.enumerated() {
            pinned.sortOrder = index
        }

        try? modelContext.save()
        Logger.pin.info("Unpinned \(itemType.rawValue) \(itemId)")
    }

    // MARK: - Reorder

    func reorder(items: [PinnedItem]) {
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
        try? modelContext.save()
        Logger.pin.info("Reordered \(items.count) pinned items")
    }
}
