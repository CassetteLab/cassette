// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog

// MARK: - Context menu preview views
// Internal (not private) so SongRow can reference SongContextPreview directly.

struct CollectionContextPreview: View {
    let coverImage: PlatformImage?
    let displayName: String
    let displaySubtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.m) {
            Group {
                if let coverImage {
                    Image(platformImage: coverImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(.secondary.opacity(0.15))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(maxWidth: 280, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !displaySubtitle.isEmpty {
                    Text(displaySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(CassetteSpacing.l)
        .frame(width: 320)
    }
}

struct SongContextPreview: View {
    let coverImage: PlatformImage?
    let song: DisplayableSong

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.m) {
            Group {
                if let coverImage {
                    Image(platformImage: coverImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(.secondary.opacity(0.15))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(maxWidth: 240, maxHeight: 240)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let artist = song.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let albumName = song.albumName {
                    Text(albumName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(CassetteSpacing.l)
        .frame(width: 280)
    }
}

// MARK: - Song context menu

/// Adds Play / Play Next / Add to Queue / Favorite actions for a single song.
struct SongContextMenuModifier: ViewModifier {
    let song: DisplayableSong
    let coverImage: PlatformImage?

    @Environment(\.appContainer) private var container

    private var isFavorite: Bool {
        container?.favoritesService.isFavorite(itemType: .song, itemId: song.id) == true
    }

    func body(content: Content) -> some View {
        content.contextMenu {
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

            Button {
                startInstantMix(from: .song(id: song.id), using: container)
            } label: {
                Label("Instant Mix", systemImage: instantMixSymbol)
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
        } preview: {
            SongContextPreview(coverImage: coverImage, song: song)
        }
    }
}

// MARK: - Collection context menu (albums and playlists)

/// Adds Play / Shuffle / Play Next / Add to Queue (when songs are provided),
/// Pin / Unpin, and Favorite (when favoriteType is non-nil) for albums and playlists.
/// `songs` defaults to empty — omit it on list rows where tracks aren't pre-loaded.
/// `favoriteType` is nil for playlists (Subsonic does not support playlist starring).
struct CollectionContextMenuModifier: ViewModifier {
    let itemType: PinnedItemType
    let itemId: String
    let displayName: String
    let displaySubtitle: String
    let coverArtId: String?
    let coverImage: PlatformImage?
    let songs: [DisplayableSong]
    let favoriteType: FavoriteType?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.appContainer) private var container
    @State private var showPinLimitAlert = false

    private var isPinned: Bool {
        container?.pinService.isPinned(itemType: itemType, itemId: itemId) == true
    }

    private var isFavorite: Bool {
        guard let ft = favoriteType else { return false }
        return container?.favoritesService.isFavorite(itemType: ft, itemId: itemId) == true
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if !songs.isEmpty {
                    Button {
                        Task {
                            do {
                                try await container?.playerService.play(tracks: songs, startIndex: 0)
                            } catch {
                                Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                            }
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }

                    Button {
                        let shuffled = songs.shuffled()
                        Task {
                            do {
                                try await container?.playerService.play(tracks: shuffled, startIndex: 0)
                            } catch {
                                Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                            }
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }

                    Button {
                        Task { await container?.playerService.playNext(songs) }
                    } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }

                    Button {
                        Task { await container?.playerService.addToQueue(songs) }
                    } label: {
                        Label("Add to Queue", systemImage: "text.append")
                    }

                    Divider()
                }

                // Instant Mix seeds from the album itself (similarity), so only albums — not playlists.
                if itemType == .album {
                    Button {
                        startInstantMix(from: .album(id: itemId), using: container)
                    } label: {
                        Label("Instant Mix", systemImage: instantMixSymbol)
                    }

                    Divider()
                }

                if isPinned {
                    Button {
                        HapticFeedback.light.trigger()
                        container?.pinService.unpin(itemType: itemType, itemId: itemId)
                    } label: {
                        Label("Unpin from Home", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        guard let serverId = container?.serverState.activeServer?.id,
                              let pin = container?.pinService else { return }
                        do {
                            try pin.pin(
                                itemType: itemType, itemId: itemId,
                                displayName: displayName, displaySubtitle: displaySubtitle,
                                coverArtId: coverArtId, serverId: serverId
                            )
                            HapticFeedback.success.trigger()
                            container?.toastService.showConfirmation("Pinned to Home")
                        } catch PinError.limitReached {
                            HapticFeedback.warning.trigger()
                            showPinLimitAlert = true
                        } catch {
                            Logger.pin.error("ItemContextMenus: pin failed — \(error)")
                        }
                    } label: {
                        Label("Pin to Home", systemImage: "pin")
                    }
                }

                if favoriteType != nil {
                    Divider()

                    Button {
                        guard let ft = favoriteType else { return }
                        let fav = isFavorite
                        Task {
                            if fav {
                                try? await container?.favoritesService.unstar(itemType: ft, itemId: itemId)
                            } else {
                                try? await container?.favoritesService.star(itemType: ft, itemId: itemId)
                            }
                        }
                    } label: {
                        Label(
                            isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: isFavorite ? "heart.slash" : "heart"
                        )
                    }
                }

                if onEdit != nil || onDelete != nil {
                    Divider()
                }

                if let onEdit {
                    Button { onEdit() } label: { Label("Edit Playlist", systemImage: "pencil") }
                }

                if let onDelete {
                    Button(role: .destructive) { onDelete() } label: { Label("Delete Playlist", systemImage: "trash") }
                }
            } preview: {
                CollectionContextPreview(
                    coverImage: coverImage,
                    displayName: displayName,
                    displaySubtitle: displaySubtitle
                )
            }
            .alert("Pin Limit Reached", isPresented: $showPinLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(PinError.limitReached.errorDescription ?? "")
            }
    }
}

// MARK: - Lazy collection context menu (albums without pre-loaded songs)

/// Like CollectionContextMenuModifier but fetches songs on-demand when a play action is tapped.
/// Use when tracks are not pre-loaded (e.g., Recently Added albums in HomeView).
struct LazyCollectionContextMenuModifier: ViewModifier {
    let itemType: PinnedItemType
    let itemId: String
    let displayName: String
    let displaySubtitle: String
    let coverArtId: String?
    let coverImage: PlatformImage?
    let favoriteType: FavoriteType?
    let songLoader: () async throws -> [DisplayableSong]

    @Environment(\.appContainer) private var container
    @State private var showPinLimitAlert = false

    private var isPinned: Bool {
        container?.pinService.isPinned(itemType: itemType, itemId: itemId) == true
    }

    private var isFavorite: Bool {
        guard let ft = favoriteType else { return false }
        return container?.favoritesService.isFavorite(itemType: ft, itemId: itemId) == true
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    Task {
                        guard let songs = try? await songLoader(), !songs.isEmpty else { return }
                        do {
                            try await container?.playerService.play(tracks: songs, startIndex: 0)
                        } catch {
                            Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                        }
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    Task {
                        guard let songs = try? await songLoader(), !songs.isEmpty else { return }
                        do {
                            try await container?.playerService.play(tracks: songs.shuffled(), startIndex: 0)
                        } catch {
                            Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                        }
                    }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }

                Button {
                    Task {
                        guard let songs = try? await songLoader(), !songs.isEmpty else { return }
                        await container?.playerService.playNext(songs)
                    }
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    Task {
                        guard let songs = try? await songLoader(), !songs.isEmpty else { return }
                        await container?.playerService.addToQueue(songs)
                    }
                } label: {
                    Label("Add to Queue", systemImage: "text.append")
                }

                Divider()

                if isPinned {
                    Button {
                        HapticFeedback.light.trigger()
                        container?.pinService.unpin(itemType: itemType, itemId: itemId)
                    } label: {
                        Label("Unpin from Home", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        guard let serverId = container?.serverState.activeServer?.id,
                              let pin = container?.pinService else { return }
                        do {
                            try pin.pin(
                                itemType: itemType, itemId: itemId,
                                displayName: displayName, displaySubtitle: displaySubtitle,
                                coverArtId: coverArtId, serverId: serverId
                            )
                            HapticFeedback.success.trigger()
                            container?.toastService.showConfirmation("Pinned to Home")
                        } catch PinError.limitReached {
                            HapticFeedback.warning.trigger()
                            showPinLimitAlert = true
                        } catch {
                            Logger.pin.error("ItemContextMenus: pin failed — \(error)")
                        }
                    } label: {
                        Label("Pin to Home", systemImage: "pin")
                    }
                }

                if favoriteType != nil {
                    Divider()

                    Button {
                        guard let ft = favoriteType else { return }
                        let fav = isFavorite
                        Task {
                            if fav {
                                try? await container?.favoritesService.unstar(itemType: ft, itemId: itemId)
                            } else {
                                try? await container?.favoritesService.star(itemType: ft, itemId: itemId)
                            }
                        }
                    } label: {
                        Label(
                            isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: isFavorite ? "heart.slash" : "heart"
                        )
                    }
                }
            } preview: {
                CollectionContextPreview(
                    coverImage: coverImage,
                    displayName: displayName,
                    displaySubtitle: displaySubtitle
                )
            }
            .alert("Pin Limit Reached", isPresented: $showPinLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(PinError.limitReached.errorDescription ?? "")
            }
    }
}

// MARK: - View extensions

extension View {
    func songContextMenu(song: DisplayableSong, coverImage: PlatformImage? = nil) -> some View {
        modifier(SongContextMenuModifier(song: song, coverImage: coverImage))
    }

    /// - Parameters:
    ///   - coverImage: Pre-loaded image from ArtworkImageCache. Pass nil to show a placeholder.
    ///   - songs: Pre-loaded tracks. Pass `[]` (default) on list rows to hide play actions.
    ///   - favoriteType: Pass `.album` for albums; `nil` for playlists (not supported by Subsonic).
    func collectionContextMenu(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String = "",
        coverArtId: String? = nil,
        coverImage: PlatformImage? = nil,
        songs: [DisplayableSong] = [],
        favoriteType: FavoriteType? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(CollectionContextMenuModifier(
            itemType: itemType,
            itemId: itemId,
            displayName: displayName,
            displaySubtitle: displaySubtitle,
            coverArtId: coverArtId,
            coverImage: coverImage,
            songs: songs,
            favoriteType: favoriteType,
            onEdit: onEdit,
            onDelete: onDelete
        ))
    }

    /// Variant for items where songs must be fetched on demand.
    /// `songLoader` is called lazily when a play action is tapped.
    func lazyCollectionContextMenu(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String = "",
        coverArtId: String? = nil,
        coverImage: PlatformImage? = nil,
        favoriteType: FavoriteType? = nil,
        songLoader: @escaping () async throws -> [DisplayableSong]
    ) -> some View {
        modifier(LazyCollectionContextMenuModifier(
            itemType: itemType,
            itemId: itemId,
            displayName: displayName,
            displaySubtitle: displaySubtitle,
            coverArtId: coverArtId,
            coverImage: coverImage,
            favoriteType: favoriteType,
            songLoader: songLoader
        ))
    }
}
