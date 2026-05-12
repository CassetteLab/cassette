// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct RecentlyPlayedSmallView: View {
    let entry: RecentlyPlayedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                WidgetCoverArtView(image: entry.coverImage)
                    .frame(width: 70, height: 70)

                Spacer()

                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer(minLength: 4)

            if let track = entry.track {
                Text(track.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            } else {
                Text("Ouvre Cassette")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
            }

            WidgetPlayButton()
        }
        .containerBackground(for: .widget) {
            entry.dominantColor
        }
    }
}
