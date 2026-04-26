// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

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
                ToolbarItem(placement: .topBarTrailing) {
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
                                Task { try? await container?.playerService.play(tracks: queue, startIndex: absoluteIndex) }
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CassetteSpacing.m)
    }
}

private struct QueueRow: View {
    let song: DisplayableSong
    let isCurrent: Bool

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
    }
}
