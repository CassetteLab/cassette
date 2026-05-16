// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EditPinnedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @Query(sort: \PinnedItem.sortOrder) private var queriedItems: [PinnedItem]
    // Local mutable copy so the drag animation isn't interrupted by @Query re-fetches.
    @State private var items: [PinnedItem] = []
    @State private var draggedItem: PinnedItem?

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
                            .opacity(draggedItem?.id == item.id ? 0.5 : 1.0)
                            .onDrag {
                                draggedItem = item
                                return NSItemProvider(object: item.id as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: PinnedItemDropDelegate(
                                    item: item,
                                    items: $items,
                                    draggedItem: $draggedItem,
                                    onReorder: { reordered in
                                        container?.pinService.reorder(items: reordered)
                                    }
                                )
                            )
                        }
                        .onDelete { offsets in
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
                }
            }
            .navigationTitle("Edit Pinned")
            .navigationBarTitleDisplayModeInline()
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

private struct PinnedItemDropDelegate: DropDelegate {
    let item: PinnedItem
    @Binding var items: [PinnedItem]
    @Binding var draggedItem: PinnedItem?
    let onReorder: ([PinnedItem]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedItem,
              draggedItem.id != item.id,
              let from = items.firstIndex(where: { $0.id == draggedItem.id }),
              let to = items.firstIndex(where: { $0.id == item.id })
        else { return }

        withAnimation {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        onReorder(items)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}
