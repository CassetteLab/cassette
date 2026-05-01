// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

/// Compact album card for horizontal-scroll discover surfaces.
/// Displays cover art, album name, and artist at a fixed 140pt width.
/// Does not include zoom transitions or context menus — those are HomeView-specific concerns.
struct AlbumCard: View {
    let album: AlbumID3

    private let cardSize: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            CoverArtCard(id: album.coverArt ?? album.id, size: cardSize)
            Text(album.name)
                .font(.cassetteCaption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
            if let artist = album.artist {
                Text(artist)
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardSize)
    }
}
