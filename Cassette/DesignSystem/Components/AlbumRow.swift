// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Flat list cell for an album — cover 60pt, name, artist, year.
/// Used in search results and any flat album list (not grids; see ArtistDetailView).
struct AlbumRow: View {
    let albumId: String
    let name: String
    let artist: String?
    let year: Int?
    let coverArtId: String?

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtCard(id: coverArtId ?? albumId, size: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let artist {
                    Text(artist)
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let year {
                    Text(String(year))
                        .font(.cassetteCaption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .contentShape(Rectangle())
        .collectionContextMenu(
            itemType: .album,
            itemId: albumId,
            displayName: name,
            displaySubtitle: artist ?? "",
            coverArtId: coverArtId,
            favoriteType: .album
        )
    }
}

#Preview {
    List {
        AlbumRow(albumId: "1", name: "Golden Hour", artist: "JVKE", year: 2022, coverArtId: nil)
        AlbumRow(albumId: "2", name: "Short n' Sweet", artist: "Sabrina Carpenter", year: 2024, coverArtId: nil)
        AlbumRow(albumId: "3", name: "Radical Optimism", artist: nil, year: nil, coverArtId: nil)
    }
    .listStyle(.plain)
}
