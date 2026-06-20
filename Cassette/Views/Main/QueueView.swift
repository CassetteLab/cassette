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
    @State private var draggedQueueIndex: Int?

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
                        QueueRow(song: song, isCurrent: false, isDragging: draggedQueueIndex == absoluteIndex)
                            .contentShape(Rectangle())
                            .opacity(draggedQueueIndex == absoluteIndex ? 0.5 : 1.0)
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
                            .onDrag {
                                // Encode the row's absolute queue position; the delegate resolves the move
                                // positionally (never by song id) so duplicate tracks reorder correctly.
                                draggedQueueIndex = absoluteIndex
                                return NSItemProvider(object: "\(absoluteIndex)" as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: QueueReorderDropDelegate(
                                targetIndex: absoluteIndex,
                                draggedIndex: $draggedQueueIndex,
                                move: { from, toOffset in
                                    Task { await container?.playerService.moveInQueue(fromIndex: from, toIndex: toOffset) }
                                }
                            ))
                    }
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
    }

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
    let isDragging: Bool

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @Environment(\.cassettePlayingAccent) private var playingAccent
    @State private var showAddToPlaylist = false
    @Query private var favoriteMatches: [FavoriteRecord]

    init(song: DisplayableSong, isCurrent: Bool, isDragging: Bool = false) {
        self.song = song
        self.isCurrent = isCurrent
        self.isDragging = isDragging
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
                ReorderIndicator(isActive: isDragging)
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
    let move: (Int, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedIndex = nil }
        guard let from = draggedIndex, from != targetIndex else { return true }
        // Land the dragged row exactly at targetIndex; moveInQueue applies dest = from < to ? to-1 : to.
        let toOffset = targetIndex > from ? targetIndex + 1 : targetIndex
        move(from, toOffset)
        return true
    }
}
