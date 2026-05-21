// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import SwiftSonic

struct CarouselAlbumCard: View {
    let album: AlbumID3

    @State private var isHovered = false
    @Environment(\.appContainer) private var container

    var body: some View {
        ZStack(alignment: .top) {
            NavigationLink(value: HomeDestination.album(album)) {
                VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                    CoverArtCard(id: album.coverArt ?? album.id, size: 180)
                        .frame(width: 180, height: 180)
                    Text(album.name)
                        .font(.cassetteCellTitle)
                        .lineLimit(1)
                    if let artist = album.artist {
                        Text(artist)
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 180)
            }
            .buttonStyle(.plain)

            if isHovered {
                Button {
                    Task {
                        guard let c = container else { return }
                        if let loaded = try? await c.libraryService.album(id: album.id),
                           let songs = loaded.song, !songs.isEmpty {
                            let tracks = songs.map { DisplayableSong(from: $0, isDownloaded: false) }
                            try? await c.playerService.play(tracks: tracks, startIndex: 0)
                        }
                    }
                } label: {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.cassetteAccent)
                        }
                }
                .buttonStyle(.plain)
                .frame(width: 180, height: 180)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .frame(width: 180)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
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
#endif
