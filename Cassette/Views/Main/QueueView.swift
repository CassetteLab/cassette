// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog

struct QueueView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
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
            .navigationTitle("Queue")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func queueList(_ playerState: PlayerState) -> some View {
        let queue = playerState.queue
        let currentIndex = playerState.currentIndex
        let upNext = Array(queue.dropFirst(currentIndex + 1))

        List {
            Section {
                queueControlsHeader(playerState)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if let current = playerState.currentTrack {
                Section("Now Playing") {
                    QueueRow(song: current, isCurrent: true)
                }
            }

            if !upNext.isEmpty {
                Section("Up Next") {
                    ForEach(Array(upNext.enumerated()), id: \.element.id) { offset, song in
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
                    }
                    .onMove { source, destination in
                        guard let relativeSource = source.first else { return }
                        let absoluteSource = currentIndex + 1 + relativeSource
                        let absoluteDestination = currentIndex + 1 + destination
                        HapticFeedback.light.trigger()
                        Task { await container?.playerService.moveInQueue(fromIndex: absoluteSource, toIndex: absoluteDestination) }
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
                    .foregroundStyle(playerState.isShuffled ? Color.cassetteAccent : Color.secondary)
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
                    .foregroundStyle(playerState.repeatMode != .off ? Color.cassetteAccent : Color.secondary)
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
                    .foregroundStyle(playerState.isAutoExtendEnabled ? Color.cassetteAccent : Color.secondary)
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
    @State private var showAddToPlaylist = false

    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtView(id: song.coverArtId ?? song.id, size: 88)
                .frame(width: 44, height: 44)
                .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.xs)

            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text(song.title)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(isCurrent ? Color.cassetteAccent : Color.primary)
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
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(Color.cassetteAccent)
                    .symbolEffect(.variableColor.iterative.reversing)
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
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
        }
    }
}
