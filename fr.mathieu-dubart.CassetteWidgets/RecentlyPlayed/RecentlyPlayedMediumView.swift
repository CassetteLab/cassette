// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import WidgetKit

struct RecentlyPlayedMediumView: View {
    let entry: RecentlyPlayedEntry

    var body: some View {
        HStack(alignment:.center,spacing: 14) {
            WidgetCoverArtView(image: entry.mainCoverImage, cornerRadius: 10)
                .frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 0) {
                
                
                Spacer()
                
                Text("ÉCOUTÉS RÉCEMMENT")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(0.5)
                    .padding(.bottom, 4)

                if let track = entry.mainTrack {
                    Text(track.title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(track.artist)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 2)
                } else {
                    Text("Ouvre Cassette pour commencer")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                WidgetPlayButton()
            }
        }
        .containerBackground(for: .widget) {
            entry.dominantColor
        }
    }
}
