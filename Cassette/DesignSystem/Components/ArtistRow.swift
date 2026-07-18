// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

/// List cell for an artist. Avatar uses the artist's initials on an accent-tinted circle
/// (Subsonic rarely provides artist artwork, so a generic placeholder is the baseline).
struct ArtistRow: View {
    let artist: ArtistID3

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtView(
                id: artist.coverArt ?? artist.id,
                size: 88,
                placeholderSystemImage: "person.fill"
            )
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let count = artist.albumCount {
                    Text("\(count) albums")
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .contentShape(Rectangle())
    }
}
