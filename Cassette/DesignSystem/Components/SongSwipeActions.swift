// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

#if os(iOS)
/// Swipe actions for a song row, mirroring what the row's context menu already offers.
///
/// Nothing here is new behaviour: the point is reach. Queueing a track or favouriting it took a
/// long press and a menu; now it takes a thumb. Full swipe is off on both edges, so the gesture
/// always lands on a button the person chose rather than firing whatever sits at the end.
struct SongSwipeActionsModifier: ViewModifier {
    let song: DisplayableSong
    let onDownload: (() -> Void)?
    /// Off where the list already owns the trailing edge — a playlist in edit mode puts
    /// "remove from playlist" there, and an explicit `.swipeActions` would silently replace it.
    let includesQueueActions: Bool

    @Environment(\.appContainer) private var container

    private var isFavorite: Bool {
        container?.favoritesService.isFavorite(itemType: .song, itemId: song.id) == true
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    let wasFavorite = isFavorite
                    Task {
                        if wasFavorite {
                            try? await container?.favoritesService.unstar(itemType: .song, itemId: song.id)
                        } else {
                            try? await container?.favoritesService.star(itemType: .song, itemId: song.id)
                        }
                    }
                } label: {
                    Label(
                        isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: isFavorite ? "star.slash" : "star"
                    )
                }
                .tint(Color.cassetteAccent)

                if let onDownload {
                    Button {
                        onDownload()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .tint(Color.cassetteAccentSecondary)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if includesQueueActions {
                    Button {
                        Task { await container?.playerService.addToQueue(song) }
                    } label: {
                        Label("Add to Queue", systemImage: "text.append")
                    }
                    .tint(Color.cassetteAccent)

                    Button {
                        Task { await container?.playerService.playNext(song) }
                    } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .tint(Color.cassetteAccentSecondary)
                }
            }
    }
}
#endif

extension View {
    /// Adds the song swipe actions on iOS; a no-op elsewhere, where a swipe means nothing.
    @ViewBuilder
    func songSwipeActions(
        song: DisplayableSong,
        onDownload: (() -> Void)? = nil,
        includesQueueActions: Bool = true
    ) -> some View {
        #if os(iOS)
        modifier(SongSwipeActionsModifier(
            song: song,
            onDownload: onDownload,
            includesQueueActions: includesQueueActions
        ))
        #else
        self
        #endif
    }
}
