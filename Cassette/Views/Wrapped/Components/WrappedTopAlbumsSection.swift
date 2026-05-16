// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopAlbumsSection: View {
    let albums: [TopAlbumEntry]

    private let columns = [
        GridItem(.flexible(), spacing: CassetteSpacing.m),
        GridItem(.flexible(), spacing: CassetteSpacing.m)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Top Albums")
                .font(.cassetteSectionTitle)
            if albums.isEmpty {
                emptyLabel("No album data for this period.")
            } else {
                LazyVGrid(columns: columns, spacing: CassetteSpacing.m) {
                    ForEach(albums.prefix(6)) { album in
                        NavigationLink {
                            AlbumDetailView(albumId: album.albumId, albumName: album.title, coverArtId: album.albumId)
                        } label: {
                            albumCard(album)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func albumCard(_ album: TopAlbumEntry) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        CoverArtView(id: album.albumId, size: 300)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
                    .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
                rankBadge(album.rank)
                    .padding(CassetteSpacing.xs)
            }
            Text(album.title)
                .font(.cassetteCellTitle)
                .lineLimit(1)
            Text(album.artistName)
                .font(.cassetteCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("#\(rank)")
            .font(.cassetteCaption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.cassetteCaption)
            .foregroundStyle(.secondary)
    }
}
