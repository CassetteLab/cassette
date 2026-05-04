// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedYearCard: View {
    let year: Int
    let firstTrack: TopTrackEntry?
    let lastTrack: TopTrackEntry?
    let playlistId: String?

    private var yearString: String { String(year) }

    var body: some View {
        Group {
            if let pid = playlistId {
                NavigationLink {
                    PlaylistDetailView(playlistId: pid, name: "Cassette Wrapped \(yearString)")
                } label: {
                    cardContent(hasPlaylist: true)
                }
                .buttonStyle(.plain)
            } else {
                cardContent(hasPlaylist: false)
            }
        }
    }

    private func cardContent(hasPlaylist: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.cassetteAccent, Color.cassetteAccent.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                    Text("Cassette Wrapped \(yearString)")
                        .font(.cassetteDetailTitle)
                        .foregroundStyle(Color.cassetteAccentText)
                    subtitleView
                        .font(.cassetteCaption)
                        .foregroundStyle(Color.cassetteAccentText.opacity(0.80))
                        .lineLimit(2)
                    if !hasPlaylist {
                        Text("Playlist not yet generated")
                            .font(.cassetteCaption)
                            .foregroundStyle(Color.cassetteAccentText.opacity(0.60))
                    }
                }
                Spacer(minLength: 0)
                if hasPlaylist {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundStyle(Color.cassetteAccentText.opacity(0.70))
                }
            }
            .padding(CassetteSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
    }

    @ViewBuilder
    private var subtitleView: some View {
        if let first = firstTrack, let last = lastTrack, first.trackId != last.trackId {
            Text("Started with \(first.title) · Ended with \(last.title)")
        } else if let first = firstTrack {
            Text("Your year started with \(first.title)")
        } else {
            Text("Your year in music")
        }
    }
}
