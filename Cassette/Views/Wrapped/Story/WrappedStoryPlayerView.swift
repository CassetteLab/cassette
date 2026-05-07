// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog

/// Full-screen annual Wrapped story player.
///
/// Navigation model (Instagram/Spotify pattern):
/// - Tap right half  → next slide
/// - Tap left half   → previous slide
/// - Hold            → pause auto-advance; release → resume
/// - Swipe down      → dismiss
/// - X button        → dismiss
///
/// Each slide auto-advances after `slideDuration` seconds.
/// The segmented progress bar at the top reflects current position.
struct WrappedStoryPlayerView: View {
    let year: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let slides = WrappedStorySlideKind.allCases
    private let slideDuration: Double = 5.0
    private let timerInterval: Double = 0.05

    @State private var currentIndex = 0
    @State private var progress: Double = 0.0
    @State private var isPaused = false
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var longPressTask: Task<Void, Never>? = nil
    @State private var wrappedData: WrappedData? = nil

    private var palette: [Color] { WrappedYearPalette.colors(for: year) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            slideContent(for: slides[currentIndex])
                .ignoresSafeArea()
                .id(currentIndex)
                .transition(.opacity)

            overlayControls

            gestureLayer
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { startTimer() }
        .onDisappear { timerTask?.cancel() }
        .task { await loadWrappedData() }
    }

    private func loadWrappedData() async {
        guard let container,
              let serverId = container.serverState.activeServer?.id.uuidString else { return }
        wrappedData = await container.statsService.wrappedData(
            for: .year(year),
            serverId: serverId,
            calendar: .current
        )
    }

    // MARK: - Overlay (progress bar + close button)

    private var overlayControls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: CassetteSpacing.s) {
                WrappedStoryProgressBar(
                    totalSlides: slides.count,
                    currentIndex: currentIndex,
                    progress: progress
                )
                Button {
                    Logger.wrappedStory.debug("[STORY] dismissed via X button at slide=\(currentIndex, privacy: .public)")
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.top, CassetteSpacing.s)
            Spacer()
        }
    }

    // MARK: - Gesture layer

    private var gestureLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { _ in
                            if longPressTask == nil {
                                longPressTask = Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    isPaused = true
                                    Logger.wrappedStory.debug("[STORY] long press — paused")
                                }
                            }
                        }
                        .onEnded { value in
                            longPressTask?.cancel()
                            longPressTask = nil
                            let wasLongPress = isPaused
                            if wasLongPress {
                                isPaused = false
                                Logger.wrappedStory.debug("[STORY] long press released — resumed")
                                return
                            }
                            if value.translation.height > 100 {
                                Logger.wrappedStory.debug("[STORY] swipe down — dismissing")
                                dismiss()
                                return
                            }
                            let dragDistance = sqrt(
                                pow(value.translation.width, 2) + pow(value.translation.height, 2)
                            )
                            guard dragDistance < 15 else { return }
                            if value.location.x < proxy.size.width / 2 {
                                goBack()
                            } else {
                                goForward()
                            }
                        }
                )
        }
        .ignoresSafeArea()
    }

    // MARK: - Slide content

    @ViewBuilder
    private func slideContent(for kind: WrappedStorySlideKind) -> some View {
        switch kind {
        case .intro:
            WrappedIntroSlide(year: year, palette: palette)
        case .minutes:
            if let data = wrappedData {
                WrappedMinutesSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .topTrack:
            if let data = wrappedData {
                WrappedTopTrackSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .topArtist:
            if let data = wrappedData {
                WrappedTopArtistSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .topAlbum:
            if let data = wrappedData {
                WrappedTopAlbumSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .topGenre:
            if let data = wrappedData {
                WrappedTopGenreSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .discoveries:
            if let data = wrappedData {
                WrappedDiscoveriesSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .closing:
            if let data = wrappedData {
                WrappedClosingSlide(year: year, data: data, palette: palette)
            } else {
                loadingSlide
            }
        }
    }

    private var loadingSlide: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)
            ProgressView().tint(.white)
        }
    }

    // MARK: - Navigation

    private func goForward() {
        HapticFeedback.light.trigger()
        if currentIndex < slides.count - 1 {
            progress = 0.0
            withAnimation(.easeInOut(duration: 0.25)) { currentIndex += 1 }
            Logger.wrappedStory.debug("[STORY] → slide \(currentIndex, privacy: .public)/\(slides.count, privacy: .public)")
        } else {
            Logger.wrappedStory.debug("[STORY] last slide reached — dismissing")
            timerTask?.cancel()
            timerTask = nil
            dismiss()
        }
    }

    private func goBack() {
        HapticFeedback.light.trigger()
        progress = 0.0
        withAnimation(.easeInOut(duration: 0.25)) {
            if currentIndex > 0 { currentIndex -= 1 }
        }
        Logger.wrappedStory.debug("[STORY] ← slide \(currentIndex, privacy: .public)/\(slides.count, privacy: .public)")
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(timerInterval * 1000)))
                guard !Task.isCancelled, !isPaused else { continue }
                progress += timerInterval / slideDuration
                if progress >= 1.0 { goForward() }
            }
        }
    }
}
