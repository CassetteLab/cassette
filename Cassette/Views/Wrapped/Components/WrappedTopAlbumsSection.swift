// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopAlbumsSection: View {
    let albums: [TopAlbumEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Top Albums")
                .font(.cassetteSectionTitle)
            if albums.isEmpty {
                Text("No album data for this period.")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(albums.prefix(3)) { album in
                    HStack(spacing: CassetteSpacing.s) {
                        Text("\(album.rank).")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title)
                                .font(.cassetteCellTitle)
                                .lineLimit(1)
                            Text(album.artistName)
                                .font(.cassetteCaption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("\(album.uniqueTracks) tracks")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
