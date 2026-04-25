// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - Song context menu

/// Adds Play / Play Next / Add to Queue / Favorite actions for a single song.
struct SongContextMenuModifier: ViewModifier {
    let song: DisplayableSong

    @Environment(\.appContainer) private var container

    private var isFavorite: Bool {
        container?.favoritesService.isFavorite(itemType: .song, itemId: song.id) == true
    }

    func body(content: Content) -> some View {
        content.contextMenu {
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
    let songs: [DisplayableSong]
    let favoriteType: FavoriteType?

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
                        Task { try? await container?.playerService.play(tracks: songs, startIndex: 0) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }

                    Button {
                        let shuffled = songs.shuffled()
                        Task { try? await container?.playerService.play(tracks: shuffled, startIndex: 0) }
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

                if isPinned {
                    Button {
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
                        } catch PinError.limitReached {
                            showPinLimitAlert = true
                        } catch {}
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
                        try? await container?.playerService.play(tracks: songs, startIndex: 0)
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    Task {
                        guard let songs = try? await songLoader(), !songs.isEmpty else { return }
                        try? await container?.playerService.play(tracks: songs.shuffled(), startIndex: 0)
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
                        } catch PinError.limitReached {
                            showPinLimitAlert = true
                        } catch {}
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
    func songContextMenu(song: DisplayableSong) -> some View {
        modifier(SongContextMenuModifier(song: song))
    }

    /// - Parameters:
    ///   - songs: Pre-loaded tracks. Pass `[]` (default) on list rows to hide play actions.
    ///   - favoriteType: Pass `.album` for albums; `nil` for playlists (not supported by Subsonic).
    func collectionContextMenu(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String = "",
        coverArtId: String? = nil,
        songs: [DisplayableSong] = [],
        favoriteType: FavoriteType? = nil
    ) -> some View {
        modifier(CollectionContextMenuModifier(
            itemType: itemType,
            itemId: itemId,
            displayName: displayName,
            displaySubtitle: displaySubtitle,
            coverArtId: coverArtId,
            songs: songs,
            favoriteType: favoriteType
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
        favoriteType: FavoriteType? = nil,
        songLoader: @escaping () async throws -> [DisplayableSong]
    ) -> some View {
        modifier(LazyCollectionContextMenuModifier(
            itemType: itemType,
            itemId: itemId,
            displayName: displayName,
            displaySubtitle: displaySubtitle,
            coverArtId: coverArtId,
            favoriteType: favoriteType,
            songLoader: songLoader
        ))
    }
}
