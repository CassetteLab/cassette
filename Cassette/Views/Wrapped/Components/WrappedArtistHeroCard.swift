// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

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
                .frame(maxWidth: .infinity, minHeight: 320)
                .background {
                    ZStack {
                        Color.black
                        blurredBackground
                        dominantColor.opacity(0.4)
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.cinematic, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: artist.artistId) {
            resolvedCoverImage = await resolveCoverImage()
        }
    }

    @ViewBuilder
    private var blurredBackground: some View {
        if let img = resolvedCoverImage {
            Image(platformImage: img)
                .resizable()
                .scaledToFill()
                .blur(radius: 60)
        } else {
            dominantColor
        }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("#1")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, CassetteSpacing.l)
                .padding(.top, CassetteSpacing.l)

            Spacer()

            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text(artist.name)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(listenTimeText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.bottom, CassetteSpacing.l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listenTimeText: String {
        let (n, u) = artist.totalSecondsListened.wrappedHeroMinutesFormat()
        return "\(n) \(u)"
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
