// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

/// Compact album card for horizontal-scroll discover surfaces.
/// Displays cover art, album name, and artist at a fixed 140pt width.
struct AlbumCard: View {
    let album: AlbumID3

    @Environment(\.appContainer) private var container

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
        .lazyCollectionContextMenu(
            itemType: .album,
            itemId: album.id,
            displayName: album.name,
            displaySubtitle: album.artist ?? "",
            coverArtId: album.coverArt,
            favoriteType: .album,
            songLoader: {
                guard let c = container else { return [] }
                let loaded = try await c.libraryService.album(id: album.id)
                return (loaded.song ?? []).map { DisplayableSong(from: $0, isDownloaded: false) }
            }
        )
    }
}
