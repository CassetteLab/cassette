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
        HStack(spacing: 12) {
            CoverArtView(
                id: playerState.currentTrack?.coverArt ?? playerState.currentTrack?.id ?? "",
                size: 44
            )
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(playerState.currentTrack?.title ?? "")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let artist = playerState.currentTrack?.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture { showingFullPlayer = true }
    }
}
