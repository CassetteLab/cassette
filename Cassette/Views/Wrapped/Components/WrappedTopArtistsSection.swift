// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct WrappedTopArtistsSection: View {
    let artists: [TopArtistEntry]

    @Environment(\.appContainer) private var container
    @State private var artistToNavigate: ArtistID3?

    private let cardSize: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Top Artists")
                .font(.cassetteSectionTitle)
            if artists.isEmpty {
                emptyLabel("No artist data for this period.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: CassetteSpacing.m) {
                        ForEach(artists.prefix(5)) { artist in
                            artistCard(artist)
                        }
                    }
                    .padding(.horizontal, CassetteSpacing.l)
                }
                .padding(.horizontal, -CassetteSpacing.l)
            }
        }
        .navigationDestination(item: $artistToNavigate) { ArtistDetailView(artist: $0) }
    }

    private func artistCard(_ artist: TopArtistEntry) -> some View {
        Button {
            Task {
                artistToNavigate = try? await container?.libraryService.artist(id: artist.artistId)
            }
        } label: {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                ZStack(alignment: .topLeading) {
                    CoverArtCard(id: artist.artistId, size: cardSize, cornerRadius: CassetteCornerRadius.large)
                    rankBadge(artist.rank)
                        .padding(CassetteSpacing.xs)
                }
                Text(artist.name)
                    .font(.cassetteCellTitle)
                    .lineLimit(1)
                Text(artist.totalSecondsListened.wrappedCompactLabel())
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: cardSize)
        }
        .buttonStyle(.plain)
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
