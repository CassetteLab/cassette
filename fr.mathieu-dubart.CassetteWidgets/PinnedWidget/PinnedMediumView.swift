// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import WidgetKit

struct PinnedMediumView: View {
    let entry: PinnedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Éléments épinglés")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "music.note")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
            }

            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Text("Épinglez des albums ou playlists dans Cassette")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 10) {
                    ForEach(entry.items.prefix(4), id: \.id) { item in
                        PinnedTileView(
                            item: item,
                            image: entry.coverImages[item.coverArtFilename ?? ""],
                            coverSize: 60
                        )
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) {
            Color("CassetteAccent")
        }
    }
}
