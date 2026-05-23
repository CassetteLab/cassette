// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog

/// Standard track cell for album and playlist detail screens.
///
/// - `showCoverArt`: show a 44pt thumbnail (useful in playlist context where tracks
///   may come from different albums). Default `false` for album tracks.
struct SongRow: View {
    let song: DisplayableSong
    let index: Int
    var showCoverArt: Bool = false
    var isFavorite: Bool = false
    var titleColor: Color = .primary
    var secondaryColor: Color = .secondary
    let onDownload: (() -> Void)?
    let onRemoveDownload: (() -> Void)?
    var isDownloading: Bool = false
    var onRemoveFromPlaylist: (() -> Void)? = nil

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?
    @State private var showAddToPlaylist = false
    #if os(macOS)
    @State private var isHovered = false
    #endif

    init(song: DisplayableSong, index: Int, showCoverArt: Bool = false, isFavorite: Bool = false, titleColor: Color = .primary, secondaryColor: Color = .secondary, onDownload: (() -> Void)? = nil, onRemoveDownload: (() -> Void)? = nil, isDownloading: Bool = false, onRemoveFromPlaylist: (() -> Void)? = nil) {
        self.song = song
        self.index = index
        self.showCoverArt = showCoverArt
        self.isFavorite = isFavorite
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.onDownload = onDownload
        self.onRemoveDownload = onRemoveDownload
        self.isDownloading = isDownloading
        self.onRemoveFromPlaylist = onRemoveFromPlaylist
    }

    private var isOnline: Bool { container?.serverState.isOnline == true }
    private var isCurrentTrack: Bool { container?.playerState.currentTrack?.id == song.id }
    private var isPlaying: Bool { container?.playerState.playbackState == .playing }

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
                    if isCurrentTrack {
                        NowPlayingBarsIndicator(isPlaying: isPlaying)
                    } else {
                        Text("\(song.trackNumber ?? index)")
                            #if os(macOS)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            #else
                            .font(.cassetteCaption)
                            .foregroundStyle(secondaryColor.opacity(0.6))
                            #endif
                            .opacity(isFavorite ? 0 : 1)
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.cassetteAccent)
                                .accessibilityLabel("Favorite")
                        }
                    }
                }
                .frame(width: 28, alignment: .trailing)
                .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    #if os(macOS)
                    .font(.system(size: 14, weight: .regular))
                    #else
                    .font(.cassetteCellTitle)
                    #endif
                    .foregroundStyle(isCurrentTrack ? Color.cassetteAccent : titleColor)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        #if os(macOS)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        #else
                        .font(.cassetteCaption)
                        .foregroundStyle(secondaryColor)
                        #endif
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
                        #if os(macOS)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        #else
                        .font(.cassetteCaption)
                        .foregroundStyle(secondaryColor.opacity(0.6))
                        #endif
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, CassetteSpacing.s)
        #if os(macOS)
        .padding(.trailing, CassetteSpacing.s)
        #endif
        .contentShape(Rectangle())
        #if os(macOS)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        #endif
        .task(id: song.id) {
            coverImage = await artworkImageCache.load(coverArtId: song.coverArtId ?? song.id)
        }
        .contextMenu {
            Button {
                Task {
                    do {
                        try await container?.playerService.play(tracks: [song], startIndex: 0)
                    } catch {
                        Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                    }
                }
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

            Button {
                showAddToPlaylist = true
            } label: {
                Label("Add to Playlist...", systemImage: "music.note.list")
            }
            .disabled(!isOnline)

            if let action = onRemoveFromPlaylist {
                Divider()
                Button(role: .destructive, action: action) {
                    Label("Remove from Playlist", systemImage: "minus.circle")
                }
            }

            if !song.isDownloaded && !isDownloading, let action = onDownload {
                Button(action: action) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }

            if song.isDownloaded, let action = onRemoveDownload {
                Button(role: .destructive, action: action) {
                    Label("Remove Download", systemImage: "trash")
                }
            }

            Divider()

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

            // TODO(v1.5.x): Add "Show in Album" and "Show in Artist". Requires:
            // (1) albumId + artistId fields on DisplayableSong, (2) NavigationPath
            // lifted into RootViewMacOS and threaded through all section views.
        } preview: {
            SongContextPreview(coverImage: coverImage, song: song)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
                .environment(artworkImageCache)
        }
    }
}
