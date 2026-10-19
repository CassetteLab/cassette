// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// One button behind a swiped song row.
///
/// The set of actions is built once (`SongSwipeActionSet`) and rendered two ways: as native
/// `.swipeActions` in a `List`, and by `SwipeRevealModifier` in a `ScrollView`, where the native
/// API does nothing. Both show the same buttons in the same order.
struct SongSwipeAction: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    var isDestructive = false
    let perform: () -> Void
}

/// What the trailing edge offers for queueing.
enum SongSwipeQueueActions {
    /// Play Next and Add to Queue — a song from anywhere in the library.
    case standard
    /// Nothing queue-related.
    case none
    /// A row that is already in the queue: "Play Next" moves it up rather than adding a copy.
    /// `nil` when the row is already next.
    case moveToNext((() -> Void)?)
}

/// A destructive "take this row out of its list" action — out of a playlist, out of the queue.
struct SongSwipeRemoval {
    let title: LocalizedStringKey
    let systemImage: String
    let perform: () -> Void
}

/// Where the row lives, which decides how the actions are drawn.
enum SongSwipePresentation {
    /// A `List` row: native `.swipeActions`.
    case list
    /// A row in a `ScrollView` / `LazyVStack`, where `.swipeActions` is a no-op.
    case scrollView
}

#if os(iOS)
@MainActor
enum SongSwipeActionSet {
    /// Favourite, then Download when there is something to fetch.
    static func leading(
        song: DisplayableSong,
        isFavorite: Bool,
        container: AppContainer?,
        onDownload: (() -> Void)?
    ) -> [SongSwipeAction] {
        var actions = [
            SongSwipeAction(
                id: "favorite",
                title: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFavorite ? "star.slash" : "star",
                tint: Color.cassetteAccent
            ) {
                Task {
                    if isFavorite {
                        try? await container?.favoritesService.unstar(itemType: .song, itemId: song.id)
                    } else {
                        try? await container?.favoritesService.star(itemType: .song, itemId: song.id)
                    }
                }
            }
        ]
        if let onDownload {
            actions.append(SongSwipeAction(
                id: "download",
                title: "Download",
                systemImage: "arrow.down.circle",
                tint: Color.cassetteAccentSecondary,
                perform: onDownload
            ))
        }
        return actions
    }

    /// Removal first — the outermost button, as in Mail — then the queue actions.
    static func trailing(
        song: DisplayableSong,
        container: AppContainer?,
        queueActions: SongSwipeQueueActions,
        removal: SongSwipeRemoval?
    ) -> [SongSwipeAction] {
        var actions: [SongSwipeAction] = []
        if let removal {
            actions.append(SongSwipeAction(
                id: "remove",
                title: removal.title,
                systemImage: removal.systemImage,
                tint: .red,
                isDestructive: true,
                perform: removal.perform
            ))
        }
        switch queueActions {
        case .standard:
            actions.append(SongSwipeAction(
                id: "add-to-queue",
                title: "Add to Queue",
                systemImage: "text.append",
                tint: Color.cassetteAccent
            ) {
                Task { await container?.playerService.addToQueue(song) }
            })
            actions.append(SongSwipeAction(
                id: "play-next",
                title: "Play Next",
                systemImage: "text.line.first.and.arrowtriangle.forward",
                tint: Color.cassetteAccentSecondary
            ) {
                Task { await container?.playerService.playNext(song) }
            })
        case .moveToNext(let move):
            if let move {
                actions.append(SongSwipeAction(
                    id: "play-next",
                    title: "Play Next",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    tint: Color.cassetteAccentSecondary,
                    perform: move
                ))
            }
        case .none:
            break
        }
        return actions
    }
}

/// Swipe actions for a song row, mirroring what the row's context menu already offers.
///
/// Nothing here is new behaviour: the point is reach. Queueing a track or favouriting it took a
/// long press and a menu; now it takes a thumb. Full swipe is off on both edges, so the gesture
/// always lands on a button the person chose rather than firing whatever sits at the end.
struct SongSwipeActionsModifier: ViewModifier {
    let song: DisplayableSong
    let onDownload: (() -> Void)?
    let queueActions: SongSwipeQueueActions
    let removal: SongSwipeRemoval?
    let presentation: SongSwipePresentation

    @Environment(\.appContainer) private var container

    private var isFavorite: Bool {
        container?.favoritesService.isFavorite(itemType: .song, itemId: song.id) == true
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let leading = SongSwipeActionSet.leading(
            song: song, isFavorite: isFavorite, container: container, onDownload: onDownload
        )
        let trailing = SongSwipeActionSet.trailing(
            song: song, container: container, queueActions: queueActions, removal: removal
        )
        switch presentation {
        case .list:
            content
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    ForEach(leading) { nativeButton($0) }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    ForEach(trailing) { nativeButton($0) }
                }
        case .scrollView:
            content.modifier(SwipeRevealModifier(leading: leading, trailing: trailing))
        }
    }

    @ViewBuilder
    private func nativeButton(_ action: SongSwipeAction) -> some View {
        if action.isDestructive {
            // System red; the destructive role also lets the List animate the row out.
            Button(role: .destructive, action: action.perform) {
                Label(action.title, systemImage: action.systemImage)
            }
        } else {
            Button(action: action.perform) {
                Label(action.title, systemImage: action.systemImage)
            }
            .tint(action.tint)
        }
    }
}
#endif

extension View {
    /// Adds the song swipe actions on iOS; a no-op elsewhere, where a swipe means nothing.
    ///
    /// - Parameters:
    ///   - onDownload: offered on the leading edge when non-nil.
    ///   - queueActions: what the trailing edge offers for queueing.
    ///   - removal: a destructive "remove from this list", outermost on the trailing edge. Pass it
    ///     where the list would otherwise own that edge (`.onDelete`): an explicit `.swipeActions`
    ///     replaces the system delete without saying so.
    ///   - presentation: `.scrollView` for rows outside a `List`, where `.swipeActions` does nothing.
    @ViewBuilder
    func songSwipeActions(
        song: DisplayableSong,
        onDownload: (() -> Void)? = nil,
        queueActions: SongSwipeQueueActions = .standard,
        removal: SongSwipeRemoval? = nil,
        presentation: SongSwipePresentation = .list
    ) -> some View {
        #if os(iOS)
        modifier(SongSwipeActionsModifier(
            song: song,
            onDownload: onDownload,
            queueActions: queueActions,
            removal: removal,
            presentation: presentation
        ))
        #else
        self
        #endif
    }
}
