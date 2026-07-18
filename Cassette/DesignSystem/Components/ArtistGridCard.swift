// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

/// An artist avatar card (circular cover + name + album count) for the artists grid, on iOS and macOS.
/// The circle fills the cell width up to a cap, so it adapts to different column counts.
struct ArtistGridCard: View {
    let artist: ArtistID3
    #if os(macOS)
    @State private var isHovered = false
    #endif

    var body: some View {
        VStack(spacing: CassetteSpacing.s) {
            CoverArtView(
                id: artist.coverArt ?? artist.id,
                size: 280,
                placeholderSystemImage: "person.fill"
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 150)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            #if os(macOS)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            #endif

            Text(artist.name)
                .font(.cassetteCellTitle)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            if let count = artist.albumCount {
                Text("\(count) albums")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
    }
}
