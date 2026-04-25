// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

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
        let coverArtId = playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id ?? ""

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
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }

                Spacer()

                CoverArtView(id: coverArtId, size: 200)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 320)
                    .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
                    .shadow(radius: 16, y: 8)

                Spacer()

                VStack(spacing: CassetteSpacing.xs) {
                    Text(playerState.currentTrack?.title ?? "")
                        .font(.cassettePlayerTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    if !playerState.isPlaybackAvailable {
                        Label("Reconnect to resume", systemImage: "wifi.slash")
                            .font(.cassetteCellSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    } else if let artist = playerState.currentTrack?.artist {
                        Text(artist)
                            .font(.cassetteCellSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, CassetteSpacing.l)

                ScrubberView(playerState: playerState, playerService: container?.playerService)
                    .padding(.top, CassetteSpacing.l)
                    .disabled(!playerState.isPlaybackAvailable)
                    .opacity(playerState.isPlaybackAvailable ? 1.0 : 0.4)

                PlaybackControlsView(playerState: playerState, playerService: container?.playerService, isPlaybackAvailable: playerState.isPlaybackAvailable)
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
                            .frame(width: 44, height: 44)
                    }

                    Button {
                        Task { await container?.playerService.toggleShuffle() }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.title3)
                            .foregroundStyle(playerState.isShuffled ? Color.cassetteAccent : .secondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.top, CassetteSpacing.l)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, CassetteSpacing.xl)
            .padding(.vertical, CassetteSpacing.l)
            .cassetteContentWidth()
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
    var isPlaybackAvailable: Bool = true

    var body: some View {
        HStack(spacing: CassetteSpacing.xxxxl) {
            Button {
                Task { try? await playerService?.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(!isPlaybackAvailable)

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
                    .background(isPlaybackAvailable ? Color.cassetteAccent : Color.secondary.opacity(0.4))
                    .clipShape(Capsule())
            }
            .disabled(!isPlaybackAvailable)

            Button {
                Task { try? await playerService?.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(!isPlaybackAvailable)
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
