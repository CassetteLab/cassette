// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData

/// Standard track cell for album and playlist detail screens.
///
/// - `showCoverArt`: show a 44pt thumbnail (useful in playlist context where tracks
///   may come from different albums). Default `false` for album tracks.
/// - `isCurrentTrack`: tints the title with `cassetteAccent`.
struct SongRow: View {
    let song: DisplayableSong
    let index: Int
    var showCoverArt: Bool = false
    var isCurrentTrack: Bool = false
    let onDownload: (() -> Void)?

    @Environment(\.appContainer) private var container
    @Query private var favoriteMatches: [FavoriteRecord]

    init(song: DisplayableSong, index: Int, showCoverArt: Bool = false, isCurrentTrack: Bool = false, onDownload: (() -> Void)? = nil) {
        self.song = song
        self.index = index
        self.showCoverArt = showCoverArt
        self.isCurrentTrack = isCurrentTrack
        self.onDownload = onDownload
        let compositeId = "song:\(song.id)"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == compositeId })
    }

    private var isFavorite: Bool { !favoriteMatches.isEmpty }
    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            if showCoverArt {
                CoverArtCard(id: song.coverArtId ?? song.id, size: 44)
            } else {
                Text("\(song.trackNumber ?? index)")
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
                Button {
                    Task {
                        if isFavorite {
                            try? await container?.favoritesService.unstar(itemType: .song, itemId: song.id)
                        } else {
                            try? await container?.favoritesService.star(itemType: .song, itemId: song.id)
                        }
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.cassetteCaption)
                        .foregroundStyle(isFavorite ? Color.cassetteAccent : Color.secondary)
                        .scaleEffect(isFavorite ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFavorite)
                }
                .buttonStyle(.borderless)
                .disabled(!isOnline)

                if song.isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.cassetteCaption)
                        .foregroundStyle(.tertiary)
                } else if let onDownload {
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                if song.duration > 0 {
                    Text(Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.cassetteCaption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, CassetteSpacing.s)
        .contentShape(Rectangle())
        .songContextMenu(song: song)
    }
}
