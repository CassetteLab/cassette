// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData

struct EditPinnedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @Query(sort: \PinnedItem.sortOrder) private var items: [PinnedItem]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView(
                        systemImage: "pin.slash",
                        title: "Nothing Pinned",
                        subtitle: "Long-press an album or playlist and choose \"Pin to Home\"."
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
                            var reordered = items
                            reordered.move(fromOffsets: from, toOffset: to)
                            container?.pinService.reorder(items: reordered)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                let item = items[index]
                                if let type = PinnedItemType(rawValue: item.itemType) {
                                    container?.pinService.unpin(itemType: type, itemId: item.itemId)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("Edit Pinned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
