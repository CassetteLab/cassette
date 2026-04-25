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
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimatingSwipe = false

    private let swipeThreshold: CGFloat = 100
    private let velocityThreshold: CGFloat = 200

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
        .offset(x: dragOffset)
        .opacity(1.0 - min(abs(dragOffset) / 200, 0.4))
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
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isAnimatingSwipe else { return }
                let h = value.translation.width
                guard abs(h) > abs(value.translation.height) else { return }
                withAnimation(.interactiveSpring()) {
                    dragOffset = h
                }
            }
            .onEnded { value in
                guard !isAnimatingSwipe else { return }
                let h = value.translation.width
                let velocity = value.velocity.width
                guard abs(h) > abs(value.translation.height) else {
                    bounceback()
                    return
                }

                let triggeredNext = h < -swipeThreshold || velocity < -velocityThreshold
                let triggeredPrev = h > swipeThreshold || velocity > velocityThreshold

                if triggeredNext || triggeredPrev {
                    commitSwipe(goNext: triggeredNext)
                } else {
                    bounceback()
                }
            }
    }

    private func commitSwipe(goNext: Bool) {
        isAnimatingSwipe = true
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        let exitOffset: CGFloat = goNext ? -300 : 300
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = exitOffset
        }

        Task {
            if goNext {
                try? await container?.playerService.skipToNext()
            } else {
                try? await container?.playerService.skipToPrevious()
            }

            let entryOffset: CGFloat = goNext ? 300 : -300
            await MainActor.run {
                dragOffset = entryOffset
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    dragOffset = 0
                }
                isAnimatingSwipe = false
            }
        }
    }

    private func bounceback() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = 0
        }
    }
}
