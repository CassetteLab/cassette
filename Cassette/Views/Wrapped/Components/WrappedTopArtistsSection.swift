// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopArtistsSection: View {
    let artists: [TopArtistEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Top Artists")
                .font(.cassetteSectionTitle)
            if artists.isEmpty {
                Text("No artist data for this period.")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(artists.prefix(3)) { artist in
                    HStack(spacing: CassetteSpacing.s) {
                        Text("\(artist.rank).")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .leading)
                        Text(artist.name)
                            .font(.cassetteCellTitle)
                        Spacer(minLength: 0)
                        Text("\(Int(artist.totalSecondsListened / 60)) min")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
