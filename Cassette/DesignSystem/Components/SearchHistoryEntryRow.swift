// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct SearchHistoryEntryRow: View {
    let entry: SearchHistoryEntry

    var body: some View {
        let _ = Self._printChanges()
        HStack(spacing: CassetteSpacing.m) {
            CoverArtView(id: entry.coverArtId ?? entry.itemId, size: 88)
                .frame(width: 44, height: 44)
                .clipShape(
                    entry.itemType == "artist"
                        ? AnyShape(Circle())
                        : AnyShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard))
                )
            Text(entry.displayName)
                .font(.cassetteCellTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .padding(.horizontal, CassetteSpacing.m)
        .contentShape(Rectangle())
    }
}
