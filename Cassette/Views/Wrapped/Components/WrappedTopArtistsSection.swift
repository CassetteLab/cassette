// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct WrappedTopArtistsSection: View {
    let artists: [TopArtistEntry]

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @Environment(DominantColorExtractor.self) private var dominantColorExtractor
    @State private var artistToNavigate: ArtistID3?
    @State private var dominantColors: [String: Color] = [:]
    @State private var coverImages: [String: PlatformImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Top Artists")
                .font(.cassetteSectionTitle)
            if artists.isEmpty {
                emptyLabel("No artist data for this period.")
            } else {
                carouselView
            }
        }
        .navigationDestination(item: $artistToNavigate) { ArtistDetailView(artist: $0) }
        .task(id: artists.map(\.artistId)) { await preloadColors() }
    }

    @ViewBuilder
    private var carouselView: some View {
        let allArtists = Array(artists.prefix(10))
        if !allArtists.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: CassetteSpacing.m) {
                    ForEach(allArtists.indices, id: \.self) { index in
                        artistCard(allArtists[index], isFirst: index == 0)
                    }
                }
                .padding(.horizontal, CassetteSpacing.l)
            }
            .padding(.horizontal, -CassetteSpacing.l)
        }
    }

    private func artistCard(_ artist: TopArtistEntry, isFirst: Bool) -> some View {
        let cardWidth: CGFloat = isFirst ? 240 : 200
        return Button {
            Task {
                artistToNavigate = try? await container?.libraryService.artist(id: artist.artistId)
            }
        } label: {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                ZStack(alignment: .topLeading) {
                    CoverArtCard(
                        id: artist.artistId,
                        size: cardWidth,
                        tier: .hero,
                        cornerRadius: CassetteCornerRadius.large,
                        initialImage: coverImages[artist.artistId]
                    )
                    dominantColors[artist.artistId, default: .clear]
                        .opacity(0.15)
                        .frame(width: cardWidth, height: cardWidth)
                        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
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
            .frame(width: cardWidth)
        }
        .buttonStyle(.plain)
    }

    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return WrappedYearPalette.medalGold
        case 2: return WrappedYearPalette.medalSilver
        case 3: return WrappedYearPalette.medalBronze
        default: return CassetteColors.accent
        }
    }

    private func rankBadge(_ rank: Int) -> some View {
        let isMedal = rank <= 3
        return Text("#\(rank)")
            .font(.cassetteCaption2)
            .fontWeight(.bold)
            .foregroundStyle(isMedal ? Color.black : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                if isMedal {
                    Capsule().fill(medalColor(for: rank))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
    }

    private func emptyLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.cassetteCaption)
            .foregroundStyle(.secondary)
    }

    private func preloadColors() async {
        let topArtists = Array(artists.prefix(10))
        var colors: [String: Color] = [:]
        var images: [String: PlatformImage] = [:]
        await withTaskGroup(of: (String, Color).self) { group in
            for artist in topArtists {
                let artistId = artist.artistId
                group.addTask { @MainActor [artworkImageCache, dominantColorExtractor] in
                    let image = await artworkImageCache.load(coverArtId: artistId)
                    let color = dominantColorExtractor.dominantColor(for: artistId, image: image)
                    return (artistId, color)
                }
            }
            for await (id, color) in group {
                colors[id] = color
            }
        }
        for artist in topArtists {
            if let image = artworkImageCache.cached(for: artist.artistId) {
                images[artist.artistId] = image
            }
        }
        dominantColors = colors
        coverImages = images
    }
}
