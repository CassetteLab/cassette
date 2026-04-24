// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct FullPlayerView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let playerState = container?.playerState {
            content(playerState)
        }
    }

    @ViewBuilder
    private func content(_ playerState: PlayerState) -> some View {
        let coverArtId = playerState.currentTrack?.coverArt ?? playerState.currentTrack?.id ?? ""

        NavigationStack {
            ZStack {
                // Blurred album cover background
                CoverArtView(id: coverArtId, size: 200)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(2)
                    .blur(radius: 60)
                    .clipped()
                    .ignoresSafeArea()

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    CoverArtCard(
                        id: coverArtId,
                        size: 320,
                        cornerRadius: CassetteCornerRadius.large
                    )
                    .padding(.horizontal, CassetteSpacing.xxxl)
                    .padding(.top, CassetteSpacing.xxl)

                    VStack(spacing: CassetteSpacing.xs) {
                        Text(playerState.currentTrack?.title ?? "")
                            .font(.cassettePlayerTitle)
                            .lineLimit(1)
                        if let artist = playerState.currentTrack?.artist {
                            Text(artist)
                                .font(.cassetteCellSubtitle)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, CassetteSpacing.xxxl)
                    .padding(.top, CassetteSpacing.xxl)

                    ScrubberView(playerState: playerState, playerService: container?.playerService)
                        .padding(.horizontal, CassetteSpacing.xxxl)
                        .padding(.top, CassetteSpacing.l)

                    PlaybackControlsView(playerState: playerState, playerService: container?.playerService)
                        .padding(.horizontal, CassetteSpacing.xxxl)
                        .padding(.top, CassetteSpacing.l)

                    HStack(spacing: CassetteSpacing.xxxxl) {
                        Button {
                            Task {
                                let next = playerState.repeatMode.next
                                await container?.playerService.setRepeatMode(next)
                            }
                        } label: {
                            Image(systemName: playerState.repeatMode.systemImage)
                                .font(.title3)
                                .foregroundStyle(playerState.repeatMode == .off ? .secondary : Color.cassetteAccent)
                        }

                        Button {
                            Task { await container?.playerService.toggleShuffle() }
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.title3)
                                .foregroundStyle(playerState.isShuffled ? Color.cassetteAccent : .secondary)
                        }
                    }
                    .padding(.top, CassetteSpacing.l)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Scrubber

private struct ScrubberView: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?

    @State private var isDragging = false
    @State private var scrubPosition: TimeInterval = 0

    private var displayPosition: TimeInterval {
        isDragging ? scrubPosition : playerState.position
    }

    var body: some View {
        VStack(spacing: CassetteSpacing.xs) {
            // On-release scrubbing: scrubPosition tracks the drag, seek fires on release.
            Slider(
                value: Binding(
                    get: { isDragging ? scrubPosition : playerState.position },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(playerState.duration, 1)
            ) { editing in
                isDragging = editing
                if !editing {
                    Task { await playerService?.seek(to: scrubPosition) }
                }
            }
            .tint(Color.cassetteAccent)

            HStack {
                Text(Duration.seconds(displayPosition).formatted(.time(pattern: .minuteSecond)))
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(Duration.seconds(max(playerState.duration - displayPosition, 0)).formatted(.time(pattern: .minuteSecond)))
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Playback controls

private struct PlaybackControlsView: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?

    var body: some View {
        HStack(spacing: CassetteSpacing.xxxxl) {
            Button {
                Task { try? await playerService?.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }

            Button {
                Task {
                    if playerState.playbackState == .playing {
                        await playerService?.pause()
                    } else {
                        await playerService?.resume()
                    }
                }
            } label: {
                Image(systemName: playerState.playbackState == .playing ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundStyle(Color.cassetteAccentText)
                    .frame(width: 72, height: 64)
                    .background(Color.cassetteAccent)
                    .clipShape(Capsule())
            }

            Button {
                Task { try? await playerService?.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
        }
    }
}

// MARK: - RepeatMode helpers

private extension RepeatMode {
    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var systemImage: String {
        switch self {
        case .off:  return "repeat"
        case .all:  return "repeat"
        case .one:  return "repeat.1"
        }
    }
}
