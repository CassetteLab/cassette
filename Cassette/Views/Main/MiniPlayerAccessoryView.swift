// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct MiniPlayerAccessoryView: View {
    @Binding var showingFullPlayer: Bool
    @Environment(\.appContainer) private var container
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimatingSwipe = false

    private let swipeThreshold: CGFloat = 100
    private let velocityThreshold: CGFloat = 200

    @State private var dominantColor: Color = .clear

    /// The bar tints itself with the current track's dominant colour, so the typography contrast is
    /// DETERMINISTIC (white on a dark cover, black on a light one) instead of following the system scheme over
    /// a glass that darkens on themed detail views.
    private var isBackgroundLight: Bool {
        dominantColor == .clear ? (colorScheme == .light) : (dominantColor.luminance > 0.6)
    }
    private var typoColor: Color { isBackgroundLight ? .black : .white }
    private var typoSecondaryColor: Color { isBackgroundLight ? Color.black.opacity(0.6) : Color.white.opacity(0.7) }

    private var currentCoverArtId: String {
        guard let ps = container?.playerState else { return "" }
        if ps.isLiveStream { return ps.currentRadio?.coverArt ?? "" }
        return ps.currentTrack?.coverArtId ?? ps.currentTrack?.id ?? ""
    }

    var body: some View {
        if let playerState = container?.playerState {
            if #available(macOS 26.0, iOS 26.0, *) {
                MiniPlayerPlacementReader { isInline in
                    playerContent(playerState, isInline: isInline)
                }
                .environment(\.colorScheme, colorScheme)
            } else {
                playerContent(playerState, isInline: false)
                    .environment(\.colorScheme, colorScheme)
            }
        }
    }

    @ViewBuilder
    private func playerContent(_ playerState: PlayerState, isInline: Bool) -> some View {
        let isLiveStream = playerState.isLiveStream
        let coverArtId = isLiveStream ? (playerState.currentRadio?.coverArt ?? "") : (playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id ?? "")
        let title = isLiveStream ? (playerState.currentRadio?.name ?? "") : (playerState.currentTrack?.title ?? "")
        let artist: String? = isLiveStream ? "Live Radio" : playerState.currentTrack?.artist
        let audioFormat: String? = isLiveStream ? nil : playerState.currentTrack?.audioFormat
        let isPlaying = playerState.playbackState == .playing
        let isAvailable = playerState.isPlaybackAvailable

        Group {
            if isInline {
                inlineBar(coverArtId: coverArtId, title: title, artist: artist, audioFormat: audioFormat, isPlaying: isPlaying, isAvailable: isAvailable, isLiveStream: isLiveStream)
                    .transition(.opacity)
            } else {
                expandedBar(playerState: playerState, coverArtId: coverArtId, title: title, artist: artist, audioFormat: audioFormat, isPlaying: isPlaying, isAvailable: isAvailable, isLiveStream: isLiveStream)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isInline)
        .offset(x: dragOffset)
        .opacity(1.0 - min(abs(dragOffset) / 200, 0.4))
        .contentShape(Rectangle())
        .onTapGesture { showingFullPlayer = true }
        .gesture(isAvailable && !isLiveStream ? swipeSkipGesture : nil)
        .task(id: currentCoverArtId) {
            let id = currentCoverArtId
            guard !id.isEmpty, let container else { dominantColor = .clear; return }
            if let cached = container.dominantColorExtractor.cachedColor(for: id), cached != .clear {
                dominantColor = cached
            } else if let image = await container.artworkImageCache.load(coverArtId: id) {
                dominantColor = container.dominantColorExtractor.dominantColor(for: id, image: image)
            }
        }
    }

    private func inlineBar(coverArtId: String, title: String, artist: String?, audioFormat: String?, isPlaying: Bool, isAvailable: Bool, isLiveStream: Bool) -> some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtCard(id: coverArtId, size: 36)
                .opacity(isAvailable ? 1.0 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.cassetteCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(typoColor)
                    .lineLimit(1)
                if !isAvailable {
                    Text("Reconnect to resume")
                        .font(.cassetteCaption)
                        .foregroundStyle(typoSecondaryColor)
                        .lineLimit(1)
                } else {
                    HStack(spacing: CassetteSpacing.xs) {
                        if let artist {
                            Text(artist)
                                .font(.cassetteCaption)
                                .foregroundStyle(typoSecondaryColor)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            playPauseButton(isPlaying: isPlaying, isAvailable: isAvailable)
        }
        .padding(.horizontal, CassetteSpacing.m)
        .padding(.vertical, CassetteSpacing.s)
    }

    private func expandedBar(playerState: PlayerState, coverArtId: String, title: String, artist: String?, audioFormat: String?, isPlaying: Bool, isAvailable: Bool, isLiveStream: Bool) -> some View {
        // While the full player covers the mini bar, skip reading position — that read is what drives the
        // capsule's per-tick (500ms) re-render, and the capsule is off-screen so its value can't be seen.
        // The `||` short-circuits before touching playerState.position when showingFullPlayer is true.
        let progress = showingFullPlayer || playerState.duration <= 0
            ? 0.0
            : playerState.position / playerState.duration
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: CassetteSpacing.m) {
                CoverArtCard(id: coverArtId, size: 36)
                    .opacity(isAvailable ? 1.0 : 0.5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.cassetteCellTitle)
                        .foregroundStyle(typoColor)
                        .lineLimit(1)
                    if !isAvailable {
                        Text("Reconnect to resume")
                            .font(.cassetteCaption)
                            .foregroundStyle(typoSecondaryColor)
                            .lineLimit(1)
                    } else {
                        HStack(spacing: CassetteSpacing.xs) {
                            if let artist {
                                Text(artist)
                                    .font(.cassetteCaption)
                                    .foregroundStyle(typoSecondaryColor)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: CassetteSpacing.s) {
                    playPauseButton(isPlaying: isPlaying, isAvailable: isAvailable)
                    if isAvailable && !isLiveStream {
                        Button {
                            HapticFeedback.light.trigger()
                            Task { try? await container?.playerService.skipToNext() }
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                                .foregroundStyle(typoColor)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Skip to next")
                    }
                }
                .frame(height: 36)
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.vertical, CassetteSpacing.m)

            if isLiveStream {
                HStack(spacing: CassetteSpacing.xs) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CassetteSpacing.l)
                .frame(height: 3)
                .accessibilityHidden(true)
            } else {
                GeometryReader { geo in
                    Capsule()
                        .fill(isAvailable ? Color.cassetteAccent : Color.secondary.opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(progress), height: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
        }
    }

    private func playPauseButton(isPlaying: Bool, isAvailable: Bool) -> some View {
        Button {
            HapticFeedback.medium.trigger()
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
                .foregroundStyle(typoColor)
                .opacity(isAvailable ? 1.0 : 0.3)
        }
        .buttonStyle(.borderless)
        .disabled(!isAvailable)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
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
        HapticFeedback.medium.trigger()

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

// Reads tabViewBottomAccessoryPlacement from the environment and passes isInline
// down as a Bool so MiniPlayerAccessoryView doesn't need to declare the
// unavailable type at struct level.
@available(macOS 26.0, iOS 26.0, *)
private struct MiniPlayerPlacementReader<Content: View>: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement: TabViewBottomAccessoryPlacement?
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(placement == .inline)
    }
}
