// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import UIKit
import WidgetKit

struct RecentlyPlayedLargeView: View {
    let entry: RecentlyPlayedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mainTrackSection

            Divider()
                .overlay(.white.opacity(0.2))

            VStack(alignment: .leading, spacing: 0) {
                Text("ÉCOUTÉS RÉCEMMENT")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(0.5)
                    .padding(.bottom, 8)

                ForEach(entry.subTracks.prefix(3), id: \.id) { track in
                    subItemRow(track: track)
                        .padding(.bottom, 10)
                }
            }

            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            Color("CassetteAccent")
        }
    }

    private var mainTrackSection: some View {
        HStack(spacing: 12) {
            WidgetCoverArtView(image: entry.mainCoverImage, cornerRadius: 10)
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 2) {
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
                        .padding(.bottom, 4)

                    WidgetPlayButton()
                } else {
                    Text("Ouvre Cassette")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "music.note")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func subItemRow(track: SharedTrackInfo) -> some View {
        HStack(spacing: 10) {
            WidgetCoverArtView(image: subCover(for: track), cornerRadius: 6)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(track.artist)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func subCover(for track: SharedTrackInfo) -> UIImage? {
        guard let filename = track.coverArtFilename else { return nil }
        return entry.subCoverImages[filename.replacingOccurrences(of: ".jpg", with: "")]
    }
}
