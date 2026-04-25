// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct MiniPlayerAccessoryView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement: TabViewBottomAccessoryPlacement?
    @State private var showingFullPlayer = false

    var body: some View {
        if let playerState = container?.playerState {
            playerContent(playerState)
                .sheet(isPresented: $showingFullPlayer) {
                    FullPlayerView()
                }
        }
    }

    @ViewBuilder
    private func playerContent(_ playerState: PlayerState) -> some View {
        let coverArtId = playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id ?? ""
        let title = playerState.currentTrack?.title ?? ""
        let artist = playerState.currentTrack?.artist
        let isPlaying = playerState.playbackState == .playing

        Group {
            if placement == .inline {
                inlineBar(coverArtId: coverArtId, title: title, artist: artist, isPlaying: isPlaying)
            } else {
                expandedBar(playerState: playerState, coverArtId: coverArtId, title: title, artist: artist, isPlaying: isPlaying)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showingFullPlayer = true }
        .gesture(swipeSkipGesture)
    }

    private func inlineBar(coverArtId: String, title: String, artist: String?, isPlaying: Bool) -> some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtCard(id: coverArtId, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.cassetteCaption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let artist {
                    Text(artist)
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            playPauseButton(isPlaying: isPlaying)
        }
        .padding(.horizontal, CassetteSpacing.m)
        .padding(.vertical, CassetteSpacing.s)
    }

    private func expandedBar(playerState: PlayerState, coverArtId: String, title: String, artist: String?, isPlaying: Bool) -> some View {
        let progress = playerState.duration > 0 ? playerState.position / playerState.duration : 0.0
        return VStack(spacing: 0) {
            HStack(spacing: CassetteSpacing.m) {
                CoverArtCard(id: coverArtId, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.cassetteCellTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let artist {
                        Text(artist)
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: CassetteSpacing.s) {
                    playPauseButton(isPlaying: isPlaying)
                    Button {
                        Task { try? await container?.playerService.skipToNext() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.vertical, CassetteSpacing.m)

            GeometryReader { geo in
                Capsule()
                    .fill(Color.cassetteAccent)
                    .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 3)
        }
    }

    private func playPauseButton(isPlaying: Bool) -> some View {
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
                .font(.title3)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.borderless)
    }

    private var swipeSkipGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let h = value.translation.width
                guard abs(h) > abs(value.translation.height) else { return }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                if h < 0 {
                    Task { try? await container?.playerService.skipToNext() }
                } else {
                    Task { try? await container?.playerService.skipToPrevious() }
                }
            }
    }
}
