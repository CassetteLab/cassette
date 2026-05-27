// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData

// MARK: - AUDIT NOTE — cascade side-effect of record()
//
// record() creates a fresh ModelContext per call (correct isolation). However,
// ctx.save() posts a store-level change notification that mainContext auto-merges.
// For NEW inserts: the merge sets all SearchHistoryEntry properties through @Model's
// @Observable setters in mainContext, firing coverArtId/serverId observations even
// though those values were never mutated post-init.
// For UPDATE (existing entry): only visitedAt is written, but the SwiftData merge
// still refreshes the full object in mainContext → same observation spray.
// The save() is not the problem; the @Query's non-entity-scoped re-evaluation is.
// See the AUDIT block in SearchView.swift for the full cascade map and fix direction.

actor SearchHistoryService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func record(itemId: String, itemType: String, displayName: String,
                coverArtId: String?, serverId: String) async {
        let ctx = ModelContext(container)
        let compositeId = "\(serverId)_\(itemId)"

        let descriptor = FetchDescriptor<SearchHistoryEntry>(
            predicate: #Predicate { $0.entryId == compositeId }
        )
        if let existing = try? ctx.fetch(descriptor).first {
            existing.visitedAt = Date()
        } else {
            ctx.insert(SearchHistoryEntry(
                itemId: itemId, itemType: itemType,
                displayName: displayName, coverArtId: coverArtId,
                serverId: serverId
            ))
            // Enforce 50-entry cap: delete oldest entries if over limit
            let all = FetchDescriptor<SearchHistoryEntry>(
                predicate: #Predicate { $0.serverId == serverId },
                sortBy: [SortDescriptor(\.visitedAt, order: .forward)]
            )
            if let entries = try? ctx.fetch(all), entries.count > 50 {
                entries.prefix(entries.count - 50).forEach { ctx.delete($0) }
            }
        }
        try? ctx.save()
    }

    func clear(serverId: String) async {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<SearchHistoryEntry>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        if let entries = try? ctx.fetch(descriptor) {
            entries.forEach { ctx.delete($0) }
            try? ctx.save()
        }
    }
}
