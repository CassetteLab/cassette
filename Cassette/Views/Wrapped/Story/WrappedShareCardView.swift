// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Render-only view for the 1080×1920 Wrapped share card.
/// Designed at 360×640 pt, rendered at @3x by ImageRenderer → 1080×1920 px.
/// Never placed in the live UI hierarchy — instantiated transiently by WrappedClosingSlide.
struct WrappedShareCardView: View {
    let year: Int
    let data: WrappedData
    let palette: [Color]

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: false)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 6) {
                    Text("YOUR")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(3.5)
                        .foregroundStyle(.white.opacity(0.7))

                    Text("\(year)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .kerning(-2.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("Wrapped")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .kerning(-1)
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    shareStatRow(
                        icon: "clock.fill",
                        primary: data.totalSecondsListened.wrappedCompactLabel(),
                        secondary: "listened this year"
                    )
                    if let track = data.topTracks.first {
                        shareStatRow(icon: "music.note", primary: track.title, secondary: track.artistName)
                    }
                    if let artist = data.topArtists.first {
                        shareStatRow(icon: "person.fill", primary: artist.name, secondary: "top artist")
                    }
                    if let genre = data.dominantGenre {
                        shareStatRow(icon: "guitars.fill", primary: genre, secondary: "top genre")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Text("Cassette")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 56)
        }
        .frame(width: 360, height: 640)
    }

    private func shareStatRow(icon: String, primary: String, secondary: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(primary)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(secondary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }
}
