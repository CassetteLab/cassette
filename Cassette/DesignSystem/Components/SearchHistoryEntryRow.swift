// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct SearchHistoryEntryRow: View {
    let entry: SearchHistoryEntry

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtCard(id: entry.coverArtId ?? entry.itemId, size: 44)
            Text(entry.displayName)
                .font(.cassetteCellTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .contentShape(Rectangle())
    }
}
