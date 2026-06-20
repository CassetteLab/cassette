// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import OSLog
import UniformTypeIdentifiers

struct QueueView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cassettePlayingAccent) private var playingAccent
    #if os(macOS)
    @State private var draggedQueueIndex: Int?
    @State private var dropTargetGap: Int?
    #endif

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Button {
                    Task {
                        guard let state = container?.playerState else { return }
                        await container?.playerService.setAutoExtendEnabled(!state.isAutoExtendEnabled)
                    }
                } label: {
                    Image(systemName: "infinity")
                        .foregroundStyle(container?.playerState.isAutoExtendEnabled == true ? playingAccent : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Auto-extend with Smart Shuffle")
                .accessibilityValue(container?.playerState.isAutoExtendEnabled == true ? "Enabled" : "Disabled")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            queueContent
        }
        #else
        NavigationStack {
            queueContent
                .navigationTitle("Queue")
                .navigationBarTitleDisplayModeInline()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    @ViewBuilder
    private var queueContent: some View {
        if let playerState = container?.playerState, !playerState.queue.isEmpty {
            queueList(playerState)
        } else {
            EmptyStateView(
                systemImage: "list.bullet",
                title: "Queue is empty",
                subtitle: "Start playing music to see your queue here."
            )
        }
    }

    @ViewBuilder
    private func queueList(_ playerState: PlayerState) -> some View {
        let queue = playerState.queue
        let currentIndex = playerState.currentIndex
        let upNext = Array(queue.dropFirst(currentIndex + 1))

        List {
            #if !os(macOS)
            Section {
                queueControlsHeader(playerState)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            #endif

            if let current = playerState.currentTrack {
                Section("Now Playing") {
                    QueueRow(song: current, isCurrent: true)
                }
            }

            if !upNext.isEmpty {
                Section("Up Next") {
                    ForEach(Array(upNext.enumerated()), id: \.offset) { offset, song in
                        let absoluteIndex = currentIndex + 1 + offset
                        QueueRow(song: song, isCurrent: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticFeedback.medium.trigger()
                                Task {
                                    do {
                                        try await container?.playerService.play(tracks: queue, startIndex: absoluteIndex)
                                    } catch {
                                        Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                                    }
                                }
                            }
                            #if os(macOS)
                            // macOS reorders by drag-and-drop; show a between-rows insertion line at the
                            // drop gap (top of the target row, or bottom of the last row for an end drop)
                            // instead of a row highlight.
                            .overlay(alignment: .top) {
                                if dropTargetGap == absoluteIndex { queueInsertionLine }
                            }
                            .overlay(alignment: .bottom) {
                                if offset == upNext.count - 1 && dropTargetGap == absoluteIndex + 1 { queueInsertionLine }
                            }
                            .onDrag {
                                // Encode the row's absolute queue position; the delegate resolves the move
                                // positionally (never by song id) so duplicate tracks reorder correctly.
                                draggedQueueIndex = absoluteIndex
                                return NSItemProvider(object: "\(absoluteIndex)" as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: QueueReorderDropDelegate(
                                targetIndex: absoluteIndex,
                                draggedIndex: $draggedQueueIndex,
                                dropTargetGap: $dropTargetGap,
                                move: { from, toOffset in
                                    Task { await container?.playerService.moveInQueue(fromIndex: from, toIndex: toOffset) }
                                }
                            ))
                            #endif
                    }
                    #if !os(macOS)
                    .onMove { source, destination in
                        // iOS uses native List reorder — offset-based, so duplicate-safe by construction.
                        // `destination` is the Array.move toOffset that moveInQueue already replicates.
                        guard let relativeSource = source.first else { return }
                        let absoluteSource = currentIndex + 1 + relativeSource
                        let absoluteDestination = currentIndex + 1 + destination
                        HapticFeedback.light.trigger()
                        Task { await container?.playerService.moveInQueue(fromIndex: absoluteSource, toIndex: absoluteDestination) }
                    }
                    #endif
                    .onDelete { indices in
                        let absoluteIndices = indices.sorted(by: >).map { currentIndex + 1 + $0 }
                        HapticFeedback.light.trigger()
                        Task {
                            for absoluteIndex in absoluteIndices {
                                await container?.playerService.removeFromQueue(at: absoluteIndex)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        #if !os(macOS)
        // iOS List reorder only engages in edit mode (per the PlaylistDetailView precedent). Keep it
        // always-on so Up Next is reorderable via the system grips without an explicit Edit toggle;
        // this is why iOS shows edit-mode chrome and tap-to-play yields to the reorder/delete affordances.
        .environment(\.editMode, .constant(.active))
        #endif
    }

    #if os(macOS)
    /// Thin accent line drawn between rows at the current drop gap (macOS drag-reorder feedback).
    private var queueInsertionLine: some View {
        Rectangle()
            .fill(playingAccent)
            .frame(height: 2)
            .padding(.horizontal, CassetteSpacing.l)
    }
    #endif

    @ViewBuilder
    private func queueControlsHeader(_ playerState: PlayerState) -> some View {
        HStack(spacing: CassetteSpacing.xxxxl) {
            Button {
                HapticFeedback.light.trigger()
                Task { await container?.playerService.toggleShuffle() }
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(playerState.isShuffled ? playingAccent : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(playerState.isShuffled ? "Shuffle On" : "Shuffle Off")

            Button {
                HapticFeedback.light.trigger()
                Task { await container?.playerService.setRepeatMode(playerState.repeatMode.next) }
            } label: {
                Image(systemName: playerState.repeatMode.systemImage)
                    .font(.title3)
                    .foregroundStyle(playerState.repeatMode != .off ? playingAccent : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Repeat: \(playerState.repeatMode == .one ? "One" : playerState.repeatMode == .off ? "Off" : "All")")

            Button {
                HapticFeedback.light.trigger()
                Task { await container?.playerService.setAutoExtendEnabled(!playerState.isAutoExtendEnabled) }
            } label: {
                Image(systemName: "infinity")
                    .font(.title3)
                    .foregroundStyle(playerState.isAutoExtendEnabled ? playingAccent : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Auto-extend with Smart Shuffle")
            .accessibilityValue(playerState.isAutoExtendEnabled ? "Enabled" : "Disabled")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CassetteSpacing.m)
    }
}

private struct QueueRow: View {
    let song: DisplayableSong
    let isCurrent: Bool

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @Environment(\.cassettePlayingAccent) private var playingAccent
    @State private var showAddToPlaylist = false
    @Query private var favoriteMatches: [FavoriteRecord]

    init(song: DisplayableSong, isCurrent: Bool) {
        self.song = song
        self.isCurrent = isCurrent
        let cid = "song:\(song.id)"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    private var isOnline: Bool { container?.serverState.isOnline == true }
    private var isPlaying: Bool { container?.playerState.playbackState == .playing }
    private var isFavorite: Bool { !favoriteMatches.isEmpty }

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtView(id: song.coverArtId ?? song.id, size: 88)
                .frame(width: 44, height: 44)
                .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.xs)

            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text(song.title)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(isCurrent ? playingAccent : Color.primary)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isCurrent {
                NowPlayingBarsIndicator(isPlaying: isPlaying)
            } else {
                #if os(macOS)
                // macOS has no edit-mode grip, so keep the visual reorder hint here; on iOS the system
                // renders its own reorder grip in edit mode, so a second one would be redundant.
                ReorderIndicator()
                #endif
            }
        }
        .padding(.vertical, CassetteSpacing.xs)
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
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
                .environment(artworkImageCache)
        }
    }
}

/// Positional drag-reorder drop delegate for the queue, shared by both queue surfaces.
///
/// Follows edit-pinned's `.onDrag`/`.onDrop` structure, with two deliberate differences:
/// - It resolves the move by **absolute queue position** (`targetIndex` + the bound grab index), not
///   edit-pinned's `firstIndex(by id)` — the queue can hold the same song twice, so an id lookup would
///   move the wrong copy; positions are unique.
/// - It commits a **single** move in `performDrop`, not per-`dropEntered`. `PlayerService` is an actor
///   and `moveInQueue` is an order-sensitive incremental mutation, so firing one unstructured `Task`
///   per hover would let commits interleave and scramble the queue; one move on drop is race-free.
///
/// `move(from:toOffset:)` receives the grabbed row's absolute index and the SwiftUI `Array.move`
/// `toOffset` for the target slot (the convention `PlayerService.moveInQueue` expects).
struct QueueReorderDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draggedIndex: Int?
    @Binding var dropTargetGap: Int?
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let from = draggedIndex else { return }
        // Track the insertion gap (== the Array.move toOffset the drop will use) so the view can draw
        // the line where the item will land. This does NOT commit — the move is applied once, on drop.
        dropTargetGap = targetIndex > from ? targetIndex + 1 : targetIndex
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedIndex = nil; dropTargetGap = nil }
        guard let from = draggedIndex, from != targetIndex else { return true }
        // Land the dragged row exactly at targetIndex; moveInQueue applies dest = from < to ? to-1 : to.
        let toOffset = targetIndex > from ? targetIndex + 1 : targetIndex
        move(from, toOffset)
        return true
    }
}
