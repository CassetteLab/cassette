// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

/// Standard track cell for album and playlist detail screens.
///
/// - `showCoverArt`: show a 44pt thumbnail (useful in playlist context where tracks
///   may come from different albums). Default `false` for album tracks.
/// - `isCurrentTrack`: tints the title with `cassetteAccent`.
/// - `isDownloaded`: shows a download badge icon.
struct SongRow: View {
    let song: Song
    let index: Int
    var showCoverArt: Bool = false
    var isDownloaded: Bool = false
    var isCurrentTrack: Bool = false

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            if showCoverArt {
                CoverArtCard(id: song.coverArt ?? song.id, size: 44)
            } else {
                Text("\(song.track ?? index)")
                    .font(.cassetteCaption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .trailing)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(isCurrentTrack ? Color.cassetteAccent : Color.primary)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: CassetteSpacing.s) {
                if isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.cassetteCaption)
                        .foregroundStyle(.tertiary)
                }
                if let duration = song.duration {
                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.cassetteCaption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, CassetteSpacing.s)
        .contentShape(Rectangle())
    }
}
