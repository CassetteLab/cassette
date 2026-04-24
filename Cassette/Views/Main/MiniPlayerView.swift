// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

/// Persistent mini-player bar anchored above the tab bar.
/// Tap anywhere to expand into FullPlayerView.
struct MiniPlayerView: View {
    @Environment(\.appContainer) private var container
    @State private var showingFullPlayer = false

    var body: some View {
        if let playerState = container?.playerState {
            bar(playerState)
                .sheet(isPresented: $showingFullPlayer) {
                    FullPlayerView()
                }
        }
    }

    private func bar(_ playerState: PlayerState) -> some View {
        let coverArtId = playerState.currentTrack?.coverArt ?? playerState.currentTrack?.id ?? ""
        let progress = playerState.duration > 0 ? playerState.position / playerState.duration : 0.0

        return VStack(spacing: 0) {
            HStack(spacing: CassetteSpacing.m) {
                CoverArtCard(id: coverArtId, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(playerState.currentTrack?.title ?? "")
                        .font(.cassetteCellTitle)
                        .lineLimit(1)
                    if let artist = playerState.currentTrack?.artist {
                        Text(artist)
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: CassetteSpacing.s) {
                    Button {
                        Task { try? await container?.playerService.skipToPrevious() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                    }

                    Button {
                        Task {
                            if playerState.playbackState == .playing {
                                await container?.playerService.pause()
                            } else {
                                await container?.playerService.resume()
                            }
                        }
                    } label: {
                        Image(systemName: playerState.playbackState == .playing ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }

                    Button {
                        Task { try? await container?.playerService.skipToNext() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                }
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.vertical, CassetteSpacing.m)

            // 3pt non-interactive progress bar
            GeometryReader { geo in
                Capsule()
                    .fill(Color.cassetteAccent)
                    .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 3)
        }
        // Use .background modifier so the blur is constrained to the VStack's natural
        // height — never fills the full screen like a ZStack with maxHeight: .infinity would.
        .background(.ultraThinMaterial)
        .background {
            CoverArtView(id: coverArtId, size: 100)
                .scaleEffect(2)
                .blur(radius: 60)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
        .padding(.horizontal, CassetteSpacing.s)
        .padding(.bottom, CassetteSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { showingFullPlayer = true }
    }
}
