// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI
import WidgetKit

struct NowPlayingSmallView: View {
    let entry: NowPlayingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                WidgetCoverArtView(image: entry.coverImage)
                    .frame(width: 65, height: 65)

                Spacer()

                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                if let track = entry.track {
                    Text(track.title)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(track.artist)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("Ouvre Cassette")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                WidgetPlayButton(isPlaying: entry.isPlaying)
                    .padding(.top, 6)
            }
        }
        .containerBackground(for: .widget) {
            entry.dominantColor
        }
    }
}
#endif
