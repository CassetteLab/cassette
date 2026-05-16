// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopTrackSlide: View {
    let data: WrappedData
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var topTrack: TopTrackEntry? { data.topTracks.first }

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(spacing: 0) {
                Spacer(minLength: CassetteSpacing.xxxxl)

                Text("YOUR #1 TRACK")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if let track = topTrack {
                    CoverArtCard(id: track.trackId, size: 200, cornerRadius: CassetteCornerRadius.large)
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)

                    Spacer(minLength: CassetteSpacing.xl)

                    VStack(spacing: CassetteSpacing.xs) {
                        Text(track.title)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .kerning(-0.5)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)

                        Text(track.artistName)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, CassetteSpacing.xl)

                    Spacer(minLength: CassetteSpacing.l)

                    Text(track.playCount.plural("play", "plays"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, CassetteSpacing.m)
                        .padding(.vertical, CassetteSpacing.s)
                        .background(Color.white.opacity(0.2), in: Capsule())
                } else {
                    Text("No track data yet")
                        .font(.system(.title2, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()
            }
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
