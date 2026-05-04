// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import OSLog
import SwiftSonic
import SwiftUI

struct WrappedArtistHeroCard: View {
    let artist: TopArtistEntry
    let dominantColor: Color
    let image: PlatformImage?
    let onTap: () -> Void

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var resolvedCoverImage: PlatformImage? = nil

    var body: some View {
        Button(action: onTap) {
            heroContent
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .bottomLeading)
                .background {
                    ZStack {
                        Color.black
                        blurredBackground
                        dominantColor.opacity(0.5)
                        Color.black.opacity(0.25)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.hero, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: artist.artistId) {
            resolvedCoverImage = await resolveCoverImage()
        }
        .onAppear {
            Logger.wrapped.debug("[HERO-CARD-DIAG] init artistId=\(artist.artistId, privacy: .public) name=\(artist.name, privacy: .public) playCount=\(artist.playCount, privacy: .public)")
            let imgDesc = image.map { "loaded \(Int($0.size.width))×\(Int($0.size.height))" } ?? "NIL"
            Logger.wrapped.debug("[HERO-CARD-DIAG] image=\(imgDesc, privacy: .public) dominantColor=\(String(describing: dominantColor), privacy: .public)")
        }
        .task(id: dominantColor) {
            Logger.wrapped.debug("[HERO-CARD-DIAG] dominantColor update=\(String(describing: dominantColor), privacy: .public) imageNil=\(image == nil, privacy: .public)")
        }
    }

    @ViewBuilder
    private var blurredBackground: some View {
        if let img = resolvedCoverImage {
            Image(platformImage: img)
                .resizable()
                .scaledToFill()
                .blur(radius: 80, opaque: true)
        } else {
            dominantColor
        }
    }

    private var heroContent: some View {
        HStack(alignment: .bottom, spacing: CassetteSpacing.m) {
            CoverArtCard(
                id: artist.artistId,
                size: 80,
                cornerRadius: CassetteCornerRadius.large,
                initialImage: resolvedCoverImage ?? image
            )
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text("#1")
                    .font(.cassetteCaption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                Text(artist.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: CassetteSpacing.xs) {
                    Text(artist.playCount.plural("play", "plays"))
                    Text("·").foregroundStyle(.white.opacity(0.4))
                    Text(artist.totalSecondsListened.wrappedCompactLabel())
                }
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(CassetteSpacing.l)
    }

    // MARK: - Cover cascade: artist coverArt → first album coverArt → prop fallback

    private func resolveCoverImage() async -> PlatformImage? {
        guard let container else { return image }
        if let artistID3 = try? await container.libraryService.artist(id: artist.artistId) {
            // Level 1: artist's own cover art
            if let coverArtId = artistID3.coverArt,
               let img = await artworkImageCache.load(coverArtId: coverArtId) {
                return img
            }
            // Level 2: first album cover art (primary fallback — album covers are always available)
            if let albumCoverArtId = artistID3.album?.first?.coverArt,
               let img = await artworkImageCache.load(coverArtId: albumCoverArtId) {
                return img
            }
        }
        // Level 3: prop passed by parent
        return image
    }
}
