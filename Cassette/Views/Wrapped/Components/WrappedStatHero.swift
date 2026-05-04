// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedStatHero: View {
    let data: WrappedData

    var body: some View {
        let palette = WrappedYearPalette.colors(for: data.period.calendarYear)
        let (number, unit) = data.totalSecondsListened.wrappedHeroFormat()

        MeshGradientBackground(palette: palette, animated: true)
            .frame(minHeight: 340)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) {
                heroContent(number: number, unit: unit)
            }
            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.hero, style: .continuous))
    }

    private func heroContent(number: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(number)
                .font(.system(size: 96, weight: .black, design: .rounded))
                .kerning(-2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, CassetteSpacing.xs)

            Color.white.opacity(0.2)
                .frame(maxWidth: .infinity)
                .frame(height: 1)
                .padding(.vertical, CassetteSpacing.m)

            HStack(spacing: CassetteSpacing.xs) {
                Text(data.totalTracksPlayed.plural("play", "plays"))
                Text("·").foregroundStyle(.white.opacity(0.4))
                Text(data.totalUniqueArtists.plural("artist", "artists"))
                Text("·").foregroundStyle(.white.opacity(0.4))
                Text(data.totalUniqueAlbums.plural("album", "albums"))
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, CassetteSpacing.xl)
        .padding(.vertical, CassetteSpacing.l)
    }
}
