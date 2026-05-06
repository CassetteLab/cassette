// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopAlbumSlide: View {
    let data: WrappedData
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var topAlbum: TopAlbumEntry? { data.topAlbums.first }

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(spacing: 0) {
                Spacer(minLength: CassetteSpacing.xxxxl)

                Text("YOUR #1 ALBUM")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if let album = topAlbum {
                    CoverArtCard(id: album.albumId, size: 200, cornerRadius: CassetteCornerRadius.large)
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)

                    Spacer(minLength: CassetteSpacing.xl)

                    VStack(spacing: CassetteSpacing.xs) {
                        Text(album.title)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .kerning(-0.5)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)

                        Text(album.artistName)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, CassetteSpacing.xl)

                    Spacer(minLength: CassetteSpacing.l)

                    Text(album.playCount.plural("play", "plays"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, CassetteSpacing.m)
                        .padding(.vertical, CassetteSpacing.s)
                        .background(Color.white.opacity(0.2), in: Capsule())
                } else {
                    Text("No album data yet")
                        .font(.system(.title2, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
