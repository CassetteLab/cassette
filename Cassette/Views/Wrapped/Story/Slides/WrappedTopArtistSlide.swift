// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopArtistSlide: View {
    let data: WrappedData
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var topArtist: TopArtistEntry? { data.topArtists.first }

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: CassetteSpacing.xxxxl)

                Text("TOP ARTIST")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if let artist = topArtist {
                    Text(artist.name)
                        .font(.system(size: 60, weight: .black, design: .rounded))
                        .kerning(-1.5)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)

                    Spacer(minLength: CassetteSpacing.l)

                    HStack(spacing: CassetteSpacing.s) {
                        statBadge(artist.playCount.plural("play", "plays"))
                        statBadge(artist.uniqueTracks.plural("track", "tracks"))
                    }
                } else {
                    Text("No artist data yet")
                        .font(.system(.title2, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()
            }
            .padding(.horizontal, CassetteSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, CassetteSpacing.m)
            .padding(.vertical, CassetteSpacing.s)
            .background(Color.white.opacity(0.2), in: Capsule())
    }
}
