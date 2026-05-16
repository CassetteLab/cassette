// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopTracksSection: View {
    let tracks: [TopTrackEntry]

    @Environment(\.appContainer) private var container

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Top Tracks")
                .font(.cassetteSectionTitle)
            if tracks.isEmpty {
                emptyLabel("No track data for this period.")
            } else {
                let visible = Array(tracks.prefix(10))
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, track in
                        trackRow(track)
                        if index < visible.count - 1 {
                            Divider()
                                .padding(.leading, CassetteSpacing.m + 28 + CassetteSpacing.m + 44 + CassetteSpacing.m)
                        }
                    }
                }
            }
        }
    }

    private func trackRow(_ track: TopTrackEntry) -> some View {
        Button {
            Task {
                guard let container else { return }
                let song = DisplayableSong(
                    id: track.trackId,
                    title: track.title,
                    artist: track.artistName,
                    albumId: nil,
                    albumName: track.albumTitle,
                    artistId: nil,
                    genre: nil,
                    duration: 0,
                    trackNumber: nil,
                    isDownloaded: false,
                    coverArtId: track.trackId,
                    audioFormat: nil
                )
                try? await container.playerService.play(tracks: [song], startIndex: 0)
            }
        } label: {
            HStack(spacing: CassetteSpacing.m) {
                ZStack {
                    Circle()
                        .fill(Color.cassetteAccent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("\(track.rank)")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.cassetteAccent)
                }
                .frame(width: 28)
                CoverArtCard(id: track.trackId, size: 44)
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
                Text(track.playCount.plural("play", "plays"))
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, CassetteSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.cassetteCaption)
            .foregroundStyle(.secondary)
    }
}
