// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedStatHero: View {
    let data: WrappedData

    var body: some View {
        let (number, unit) = data.totalSecondsListened.wrappedHeroFormat()
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            Text(number)
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.cassetteAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(.cassetteDetailTitle)
                .foregroundStyle(.primary)
            HStack(spacing: CassetteSpacing.xs) {
                Text(data.totalTracksPlayed.plural("play", "plays"))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(data.totalUniqueArtists.plural("artist", "artists"))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(data.totalUniqueAlbums.plural("album", "albums"))
            }
            .font(.cassetteCaption)
            .foregroundStyle(.secondary)
        }
        .padding(CassetteSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cassetteAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
    }
}
