// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI
import WidgetKit

struct PinnedLargeView: View {
    let entry: PinnedEntry

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pinned Items")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "music.note")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
            }

            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Text("Pin albums or playlists in Cassette")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(entry.items.prefix(6), id: \.id) { item in
                        PinnedTileView(
                            item: item,
                            image: entry.coverImages[item.coverArtFilename ?? ""],
                            coverSize: 80
                        )
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) {
            Color("CassetteAccent")
        }
    }
}
#endif
