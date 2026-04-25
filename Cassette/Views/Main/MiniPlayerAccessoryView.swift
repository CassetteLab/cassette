// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct MiniPlayerAccessoryView: View {
    @Binding var showingFullPlayer: Bool
    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement: TabViewBottomAccessoryPlacement?
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimatingSwipe = false
    @State private var dominantColor: Color = .clear
    @State private var isLightBackground: Bool = false

    private let swipeThreshold: CGFloat = 100
    private let velocityThreshold: CGFloat = 200

    private var typoColor: Color {
        dominantColor == .clear ? .primary : (isLightBackground ? .black : .white)
    }
    private var typoSecondaryColor: Color {
        dominantColor == .clear ? .secondary : (isLightBackground ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
    }

    var body: some View {
        if let playerState = container?.playerState {
            playerContent(playerState)
                .background(
                    dominantColor.opacity(0.85)
                        .animation(.easeInOut(duration: 0.3), value: dominantColor)
                )
                .task(id: playerState.currentTrack?.coverArtId) {
                    await updateDominantColor(coverArtId: playerState.currentTrack?.coverArtId)
                }
        }
    }

    @ViewBuilder
    private func playerContent(_ playerState: PlayerState) -> some View {
        let coverArtId = playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id ?? ""
        let title = playerState.currentTrack?.title ?? ""
        let artist = playerState.currentTrack?.artist
        let audioFormat = playerState.currentTrack?.audioFormat
        let isPlaying = playerState.playbackState == .playing
        let isAvailable = playerState.isPlaybackAvailable

        Group {
            if placement == .inline {
                inlineBar(coverArtId: coverArtId, title: title, artist: artist, audioFormat: audioFormat, isPlaying: isPlaying, isAvailable: isAvailable)
                    .transition(.opacity)
            } else {
                expandedBar(playerState: playerState, coverArtId: coverArtId, title: title, artist: artist, audioFormat: audioFormat, isPlaying: isPlaying, isAvailable: isAvailable)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: placement == .inline)
        .offset(x: dragOffset)
        .opacity(1.0 - min(abs(dragOffset) / 200, 0.4))
        .contentShape(Rectangle())
        .onTapGesture { showingFullPlayer = true }
        .gesture(isAvailable ? swipeSkipGesture : nil)
    }

    private func inlineBar(coverArtId: String, title: String, artist: String?, audioFormat: String?, isPlaying: Bool, isAvailable: Bool) -> some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtCard(id: coverArtId, size: 36)
                .opacity(isAvailable ? 1.0 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.cassetteCaption)
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
                        if let format = audioFormat {
                            AudioFormatBadge(format: format)
                                .layoutPriority(1)
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

    private func expandedBar(playerState: PlayerState, coverArtId: String, title: String, artist: String?, audioFormat: String?, isPlaying: Bool, isAvailable: Bool) -> some View {
        let progress = playerState.duration > 0 ? playerState.position / playerState.duration : 0.0
        return VStack(spacing: 0) {
            HStack(spacing: CassetteSpacing.m) {
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
                            if let format = audioFormat {
                                AudioFormatBadge(format: format)
                                    .layoutPriority(1)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: CassetteSpacing.s) {
                    playPauseButton(isPlaying: isPlaying, isAvailable: isAvailable)
                    if isAvailable {
                        Button {
                            HapticFeedback.light.trigger()
                            Task { try? await container?.playerService.skipToNext() }
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                                .foregroundStyle(typoColor)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.vertical, CassetteSpacing.m)

            GeometryReader { geo in
                Capsule()
                    .fill(isAvailable ? Color.cassetteAccent : Color.secondary.opacity(0.3))
                    .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 3)
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
    }

    private func updateDominantColor(coverArtId: String?) async {
        guard let coverArtId else {
            withAnimation(.easeInOut(duration: 0.3)) {
                dominantColor = .clear
                isLightBackground = false
            }
            return
        }
        if let localURL = await container?.downloadService.localCoverArtURL(forId: coverArtId) {
            await extractAndSetColor(coverArtId: coverArtId, from: localURL)
            return
        }
        guard let url = await container?.libraryService.coverArtURL(id: coverArtId, size: 100) else { return }
        await extractAndSetColor(coverArtId: coverArtId, from: url)
    }

    private func extractAndSetColor(coverArtId: String, from url: URL) async {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = PlatformImage(data: data) else { return }
        let color = colorExtractor.dominantColor(for: coverArtId, image: image)
        let luminance = computeLuminance(of: color)
        withAnimation(.easeInOut(duration: 0.3)) {
            dominantColor = color
            isLightBackground = luminance > 0.6
        }
    }

    private func computeLuminance(of color: Color) -> Double {
        guard let components = color.cgColor?.components, components.count >= 3 else { return 0.5 }
        return 0.299 * Double(components[0]) + 0.587 * Double(components[1]) + 0.114 * Double(components[2])
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
