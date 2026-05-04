// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedArtistHeroCard: View {
    let artist: TopArtistEntry
    let dominantColor: Color
    let image: PlatformImage?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                blurredBackground
                dominantColor.opacity(0.5)
                Color.black.opacity(0.25)
                heroContent
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.hero, style: .continuous))
    }

    @ViewBuilder
    private var blurredBackground: some View {
        if let image {
            Image(platformImage: image)
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
                initialImage: image
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
}
