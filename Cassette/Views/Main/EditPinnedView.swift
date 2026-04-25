// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData

struct EditPinnedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @Query(sort: \PinnedItem.sortOrder) private var queriedItems: [PinnedItem]
    // Local mutable copy so the drag animation isn't interrupted by @Query re-fetches.
    @State private var items: [PinnedItem] = []
    // A proper @State binding lets SwiftUI's List write to editMode during drag operations.
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty && queriedItems.isEmpty {
                    EmptyStateView(
                        systemImage: "pin",
                        title: "Nothing pinned yet",
                        subtitle: "Long-press an album or playlist to pin it to your home screen."
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            HStack(spacing: CassetteSpacing.m) {
                                CoverArtCard(id: item.coverArtId ?? item.itemId, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName)
                                        .font(.cassetteCellTitle)
                                        .lineLimit(1)
                                    if !item.displaySubtitle.isEmpty {
                                        Text(item.displaySubtitle)
                                            .font(.cassetteCaption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, CassetteSpacing.xs)
                        }
                        .onMove { from, to in
                            // Mutate local state first for instant visual feedback,
                            // then persist the new order.
                            items.move(fromOffsets: from, toOffset: to)
                            container?.pinService.reorder(items: items)
                        }
                        .onDelete { offsets in
                            // Remove locally first for instant visual feedback,
                            // then unpin from the persistent store.
                            let toUnpin = offsets.map { items[$0] }
                            items.remove(atOffsets: offsets)
                            for item in toUnpin {
                                if let type = PinnedItemType(rawValue: item.itemType) {
                                    container?.pinService.unpin(itemType: type, itemId: item.itemId)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationTitle("Edit Pinned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                items = queriedItems
            }
            .onChange(of: queriedItems.count) { _, _ in
                // Sync only on count changes (pin/unpin from outside the sheet).
                // Reorder changes are already reflected in local state; syncing on
                // every @Query refresh would interrupt an in-progress drag.
                items = queriedItems
            }
        }
    }
}
