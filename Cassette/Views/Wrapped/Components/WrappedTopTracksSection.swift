// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopTracksSection: View {
    let tracks: [TopTrackEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Top Tracks")
                .font(.cassetteSectionTitle)
            if tracks.isEmpty {
                Text("No track data for this period.")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tracks.prefix(5)) { track in
                    HStack(spacing: CassetteSpacing.s) {
                        Text("\(track.rank).")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.cassetteCellTitle)
                                .lineLimit(1)
                            Text(track.artistName)
                                .font(.cassetteCaption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("\(track.playCount)x")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
