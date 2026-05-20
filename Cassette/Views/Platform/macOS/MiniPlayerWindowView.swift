// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI

struct MiniPlayerWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var container: AppContainer? = AppContainer.shared
    @State private var isScrubbing = false
    @State private var localScrubPosition: Double = 0
    @State private var isMuted = false
    @AppStorage("cassette.lastVolume") private var localVolume: Double = 0.7

    private var playerState: PlayerState? { container?.playerState }
    private var currentTrack: DisplayableSong? { playerState?.currentTrack }
    private var isPlaying: Bool { playerState?.playbackState == .playing }
    private var isLoading: Bool { playerState?.playbackState == .loading }
    private var noTrack: Bool { currentTrack == nil }

    var body: some View {
        ZStack {
            MiniPlayerWindowConfigurator()
                .frame(width: 0, height: 0)

            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    artwork

                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentTrack?.title ?? "No track playing")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(noTrack ? .secondary : .primary)
                        Text(artistLine)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    controls
                }

                scrubber
            }
            .padding(.top, 20)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 320, height: 136)
        .background {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
            } else {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(alignment: .topLeading) {
            closeButton
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Subviews

    private var artwork: some View {
        Group {
            if let track = currentTrack {
                CoverArtView(id: track.coverArtId ?? track.id, size: 44)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                Task { try? await container?.playerService.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(noTrack ? .quaternary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)

            playPauseButton

            Button {
                Task { try? await container?.playerService.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(noTrack ? .quaternary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)
        }
    }

    @ViewBuilder
    private var playPauseButton: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
        } else {
            Button {
                Task {
                    if isPlaying {
                        await container?.playerService.pause()
                    } else {
                        await container?.playerService.resume()
                    }
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(noTrack ? .secondary : .primary)
                    .frame(width: 24, height: 24)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(noTrack)
        }
    }

    private var scrubber: some View {
        ProgressSlider(
            value: Binding(
                get: { isScrubbing ? localScrubPosition : (playerState?.position ?? 0) },
                set: { localScrubPosition = $0 }
            ),
            total: max(1, playerState?.duration ?? 1),
            onEditingChanged: { editing in
                if editing { localScrubPosition = playerState?.position ?? 0 }
                isScrubbing = editing
                if !editing {
                    let pos = localScrubPosition
                    Task { await container?.playerService.seek(to: pos) }
                }
            },
            trackColor: .primary.opacity(0.15),
            fillColor: .primary,
            height: 8,
            trackHeight: 2
        )
        .disabled(noTrack)
        .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button {
            NSApplication.shared.keyWindow?.close()
            NotificationCenter.default.post(name: .cassetteOpenFullPlayer, object: nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(14)
    }

    // MARK: - Helpers

    private var artistLine: String {
        let parts = [currentTrack?.artist, currentTrack?.albumName].compactMap { $0 }
        return parts.isEmpty ? " " : parts.joined(separator: " — ")
    }
}
#endif
