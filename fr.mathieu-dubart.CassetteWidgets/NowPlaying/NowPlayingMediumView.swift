// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI
import WidgetKit

struct NowPlayingMediumView: View {
    let entry: NowPlayingEntry

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            WidgetCoverArtView(image: entry.coverImage, cornerRadius: 10)
                .frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 0) {

                Text("À L'ÉCOUTE")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(0.5)
                    .padding(.bottom, 4)

                if let track = entry.track {
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

                WidgetPlayButton(isPlaying: entry.isPlaying)
            }

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 0) {
                VStack {
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.top, 2)

                    Spacer()
                }
            }
        }
        .containerBackground(for: .widget) {
            entry.dominantColor
        }
    }
}
#endif
