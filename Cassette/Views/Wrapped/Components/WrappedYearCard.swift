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

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            gradientHeader
            if let pid = playlistId {
                playlistLink(pid)
            }
        }
    }

    private var gradientHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.cassetteAccent, Color.cassetteAccent.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text("Cassette Wrapped \(year)")
                    .font(.cassetteDetailTitle)
                    .foregroundStyle(Color.cassetteAccentText)
                subtitle
                    .font(.cassetteCaption)
                    .foregroundStyle(Color.cassetteAccentText.opacity(0.80))
                    .lineLimit(2)
            }
            .padding(CassetteSpacing.l)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large, style: .continuous))
    }

    @ViewBuilder
    private var subtitle: some View {
        if let first = firstTrack, let last = lastTrack, first.trackId != last.trackId {
            Text("Started with \(first.title) · Ended with \(last.title)")
        } else if let first = firstTrack {
            Text("Your year started with \(first.title)")
        } else {
            Text("Your year in music")
        }
    }

    private func playlistLink(_ pid: String) -> some View {
        NavigationLink {
            PlaylistDetailView(playlistId: pid, name: "Cassette Wrapped \(year)")
        } label: {
            HStack {
                Image(systemName: "music.note.list")
                    .font(.body)
                    .foregroundStyle(Color.cassetteAccent)
                Text("Open Playlist")
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(CassetteSpacing.m)
            .background(Color.cassetteAccent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
