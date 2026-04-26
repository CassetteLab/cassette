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
    var titleColor: Color = .primary
    var secondaryColor: Color = .secondary
    let onDownload: (() -> Void)?
    var isDownloading: Bool = false

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @Query private var favoriteMatches: [FavoriteRecord]
    @State private var coverImage: PlatformImage?

    init(song: DisplayableSong, index: Int, showCoverArt: Bool = false, isCurrentTrack: Bool = false, titleColor: Color = .primary, secondaryColor: Color = .secondary, onDownload: (() -> Void)? = nil, isDownloading: Bool = false) {
        self.song = song
        self.index = index
        self.showCoverArt = showCoverArt
        self.isCurrentTrack = isCurrentTrack
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.onDownload = onDownload
        self.isDownloading = isDownloading
        let compositeId = "song:\(song.id)"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == compositeId })
    }

    private var isFavorite: Bool { !favoriteMatches.isEmpty }
    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        HStack(spacing: CassetteSpacing.s) {
            if showCoverArt {
                CoverArtCard(id: song.coverArtId ?? song.id, size: 44)
                    .overlay(alignment: .topLeading) {
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.cassetteAccent)
                                .padding(3)
                        }
                    }
            } else {
                ZStack {
                    Text("\(song.trackNumber ?? index)")
                        .font(.cassetteCaption)
                        .foregroundStyle(secondaryColor.opacity(0.6))
                        .opacity(isFavorite ? 0 : 1)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.cassetteAccent)
                            .accessibilityLabel("Favorite")
                    }
                }
                .frame(width: 28, alignment: .trailing)
                .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(isCurrentTrack ? Color.cassetteAccent : titleColor)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.cassetteCaption)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: CassetteSpacing.s) {
                if song.isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.cassetteCaption)
                        .foregroundStyle(secondaryColor.opacity(0.6))
                } else if isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }
                if song.duration > 0 {
                    Text(Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.cassetteCaption)
                        .foregroundStyle(secondaryColor.opacity(0.6))
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, CassetteSpacing.s)
        .contentShape(Rectangle())
        .task(id: song.id) {
            coverImage = await artworkImageCache.load(coverArtId: song.coverArtId ?? song.id)
        }
        .contextMenu {
            Button {
                Task { try? await container?.playerService.play(tracks: [song], startIndex: 0) }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                Task { await container?.playerService.playNext(song) }
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                Task { await container?.playerService.addToQueue(song) }
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }

            Divider()

            if !song.isDownloaded && !isDownloading, let action = onDownload {
                Button(action: action) {
                    Label("Download", systemImage: "arrow.down.circle")
                }

                Divider()
            }

            Button {
                let fav = isFavorite
                Task {
                    if fav {
                        try? await container?.favoritesService.unstar(itemType: .song, itemId: song.id)
                    } else {
                        try? await container?.favoritesService.star(itemType: .song, itemId: song.id)
                    }
                }
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
            .disabled(!isOnline)
        } preview: {
            SongContextPreview(coverImage: coverImage, song: song)
        }
    }
}
