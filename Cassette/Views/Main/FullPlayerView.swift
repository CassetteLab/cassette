// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData

#if canImport(UIKit)
import AVKit
#endif

struct FullPlayerView: View {
    @Binding var isPresented: Bool
    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor

    @State private var vm = FullPlayerViewModel()
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var dragOffsetY: CGFloat = 0

    private let dismissThreshold: CGFloat = 100
    private let dismissVelocityThreshold: CGFloat = 500

    var body: some View {
        if let playerState = container?.playerState {
            content(playerState)
                .task(id: playerState.currentTrack?.coverArtId) {
                    await vm.updateColors(for: playerState.currentTrack?.coverArtId, colorExtractor: colorExtractor, container: container)
                }
                .onAppear { dragOffsetY = 0 }
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private func content(_ playerState: PlayerState) -> some View {
        let coverArtId = playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id ?? ""
        let isPlaying = playerState.playbackState == .playing

        VStack(spacing: 0) {
            topBar
                .padding(.top, CassetteSpacing.s)

            Spacer(minLength: CassetteSpacing.l)

            // Color.clear is the layout anchor — its size is fully determined by the
            // offered space, so AsyncImage's image intrinsics never affect VStack layout.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 280)
                .overlay {
                    CoverArtView(id: coverArtId, size: 300)
                }
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
                .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
                .scaleEffect(isPlaying ? 1.0 : 0.92)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isPlaying)
                .padding(.horizontal, CassetteSpacing.xl)

            Spacer(minLength: CassetteSpacing.l)

            TrackInfoSection(
                playerState: playerState,
                container: container,
                contentColor: vm.contentColor,
                secondaryContentColor: vm.secondaryContentColor,
                glassTint: vm.glassTint
            )
            .padding(.horizontal, CassetteSpacing.l)

            ScrubberView(
                playerState: playerState,
                playerService: container?.playerService,
                contentColor: vm.contentColor,
                secondaryContentColor: vm.secondaryContentColor
            )
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.top, CassetteSpacing.m)
            .disabled(!playerState.isPlaybackAvailable)
            .opacity(playerState.isPlaybackAvailable ? 1.0 : 0.4)

            PlaybackControlsView(
                playerState: playerState,
                playerService: container?.playerService,
                isPlaybackAvailable: playerState.isPlaybackAvailable,
                contentColor: vm.contentColor,
                secondaryContentColor: vm.secondaryContentColor,
                glassTint: vm.glassTint
            )
            .padding(.top, CassetteSpacing.l)

            VolumeSection(contentColor: vm.contentColor, secondaryContentColor: vm.secondaryContentColor)
                .padding(.horizontal, CassetteSpacing.l)
                .padding(.top, CassetteSpacing.l)

            BottomToolbar(
                showLyrics: $showLyrics,
                showQueue: $showQueue,
                secondaryContentColor: vm.secondaryContentColor,
                glassTint: vm.glassTint
            )
            .padding(.top, CassetteSpacing.l)

            Spacer(minLength: CassetteSpacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cassetteContentWidth()
        .offset(y: max(dragOffsetY, 0))
        .opacity(1.0 - min(dragOffsetY / 500, 0.5))
        .gesture(swipeDownGesture)
        .background {
            ZStack {
                Color.black
                if let coverImage = vm.coverImage {
                    Image(platformImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(1.3)
                        .blur(radius: 80, opaque: true)
                        .transition(.opacity)
                }
                vm.dominantColor.opacity(0.5)
                Color.black.opacity(0.25)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLyrics) {
            LyricsView(song: playerState.currentTrack)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
                .presentationDetents([.large])
        }
    }

    private var topBar: some View {
        Capsule()
            .fill(vm.contentColor.opacity(0.4))
            .frame(width: 36, height: 5)
            .accessibilityHidden(true)
    }

    private var swipeDownGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let dy = value.translation.height
                let dx = value.translation.width
                guard dy > 0, dy > abs(dx) else { return }
                dragOffsetY = dy
            }
            .onEnded { value in
                let dy = value.translation.height
                let velocity = value.velocity.height
                if dy > dismissThreshold || velocity > dismissVelocityThreshold {
                    withAnimation(.easeIn(duration: 0.2)) { dragOffsetY = 800 }
                    Task {
                        try? await Task.sleep(for: .milliseconds(210))
                        await MainActor.run { isPresented = false }
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffsetY = 0 }
                }
            }
    }
}

// MARK: - Track info section (own @Query for reactive favorite state)

private struct TrackInfoSection: View {
    let playerState: PlayerState
    let container: AppContainer?
    let contentColor: Color
    let secondaryContentColor: Color
    let glassTint: Color

    @Query private var favoriteMatches: [FavoriteRecord]

    init(playerState: PlayerState, container: AppContainer?, contentColor: Color, secondaryContentColor: Color, glassTint: Color) {
        self.playerState = playerState
        self.container = container
        self.contentColor = contentColor
        self.secondaryContentColor = secondaryContentColor
        self.glassTint = glassTint
        let cid = "song:\(playerState.currentTrack?.id ?? "")"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    private var isFavorite: Bool { !favoriteMatches.isEmpty }
    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        HStack(alignment: .top, spacing: CassetteSpacing.m) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text(playerState.currentTrack?.title ?? "")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(contentColor)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if !playerState.isPlaybackAvailable {
                    Label("Reconnect to resume", systemImage: "wifi.slash")
                        .font(.callout)
                        .foregroundStyle(secondaryContentColor)
                        .lineLimit(1)
                } else {
                    HStack(spacing: CassetteSpacing.xs) {
                        if let album = playerState.currentTrack?.albumName {
                            Text(album)
                                .font(.callout)
                                .foregroundStyle(secondaryContentColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let format = playerState.currentTrack?.audioFormat {
                            AudioFormatBadge(format: format)
                        }
                    }
                    if let artist = playerState.currentTrack?.artist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(secondaryContentColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: CassetteSpacing.s) {
                Button {
                    HapticFeedback.light.trigger()
                    let fav = isFavorite
                    let songId = playerState.currentTrack?.id ?? ""
                    Task {
                        if fav {
                            try? await container?.favoritesService.unstar(itemType: .song, itemId: songId)
                        } else {
                            try? await container?.favoritesService.star(itemType: .song, itemId: songId)
                        }
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(isFavorite ? Color.cassetteAccent : contentColor)
                        .cassetteGlassButton(size: 44, tint: glassTint)
                }
                .buttonStyle(.borderless)
                .disabled(!isOnline)
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")

                Menu {
                    Button("Go to Album", systemImage: "square.stack") { }
                    Button("Go to Artist", systemImage: "music.mic") { }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundStyle(contentColor)
                        .cassetteGlassButton(size: 44, tint: glassTint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
            }
        }
    }
}

// MARK: - Scrubber

private struct ScrubberView: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?
    let contentColor: Color
    let secondaryContentColor: Color

    @State private var isDragging = false
    @State private var displayPosition: TimeInterval = 0

    // Prefer AVPlayer-reported duration; fall back to song metadata to avoid slider clamping to 0..1
    private var effectiveDuration: TimeInterval {
        playerState.duration > 0 ? playerState.duration : (playerState.currentTrack?.duration ?? 1)
    }

    private var shownPosition: TimeInterval {
        isDragging ? displayPosition : playerState.position
    }

    // ProgressSlider writes dragged values here; reads live AVPlayer position when not dragging.
    private var positionBinding: Binding<TimeInterval> {
        Binding(
            get: { playerState.position },
            set: { displayPosition = $0 }
        )
    }

    var body: some View {
        VStack(spacing: CassetteSpacing.xs) {
            ProgressSlider(
                value: positionBinding,
                total: effectiveDuration,
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        Task { await playerService?.seek(to: displayPosition) }
                    }
                },
                trackColor: contentColor.opacity(0.2),
                fillColor: contentColor.opacity(0.95)
            )

            HStack {
                Text(Duration.seconds(shownPosition).formatted(.time(pattern: .minuteSecond)))
                    .font(.cassetteCaption)
                    .foregroundStyle(secondaryContentColor)
                    .monospacedDigit()
                Spacer()
                Text(Duration.seconds(max(effectiveDuration - shownPosition, 0)).formatted(.time(pattern: .minuteSecond)))
                    .font(.cassetteCaption)
                    .foregroundStyle(secondaryContentColor)
                    .monospacedDigit()
            }
        }
    }
}

struct ProgressSlider: View {
    @Binding var value: TimeInterval
    let total: TimeInterval
    let onEditingChanged: (Bool) -> Void
    var trackColor: Color = Color.white.opacity(0.2)
    var fillColor: Color = Color.white.opacity(0.95)

    @State private var isDragging = false
    @State private var dragValue: TimeInterval?

    var body: some View {
        GeometryReader { geo in
            let trackW = geo.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)

                Capsule()
                    .fill(fillColor)
                    .frame(width: progressWidth(in: trackW))
            }
            .frame(height: isDragging ? 12 : 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                            HapticFeedback.light.trigger()
                        }
                        let ratio = gesture.location.x / trackW
                        let clampedRatio = max(0, min(1, ratio))
                        dragValue = total * clampedRatio
                        value = dragValue ?? value
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragValue = nil
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 32)
        .accessibilityLabel("Playback position")
        .accessibilityValue(Duration.seconds(value).formatted(.time(pattern: .minuteSecond)))
        .accessibilityAdjustableAction { direction in
            let step = total * 0.05
            switch direction {
            case .increment:
                value = min(value + step, total)
                onEditingChanged(false)
            case .decrement:
                value = max(value - step, 0)
                onEditingChanged(false)
            @unknown default: break
            }
        }
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let displayedValue = dragValue ?? value
        return max(0, (CGFloat(displayedValue) / CGFloat(total)) * totalWidth)
    }
}

// MARK: - Playback controls

private struct PlaybackControlsView: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?
    var isPlaybackAvailable: Bool = true
    let contentColor: Color
    let secondaryContentColor: Color
    let glassTint: Color

    var body: some View {
        HStack(spacing: CassetteSpacing.xxxxl) {
            Button {
                HapticFeedback.light.trigger()
                Task { try? await playerService?.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(contentColor)
                    .cassetteGlassButton(size: 56, tint: glassTint)
            }
            .disabled(!isPlaybackAvailable)
            .accessibilityLabel("Skip to previous")

            Button {
                HapticFeedback.medium.trigger()
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
                    .foregroundStyle(isPlaybackAvailable ? Color.cassetteAccentText : contentColor.opacity(0.5))
                    .cassetteGlassButton(size: 80, tint: isPlaybackAvailable ? Color.cassetteAccent : nil)
            }
            .disabled(!isPlaybackAvailable)
            .accessibilityLabel(playerState.playbackState == .playing ? "Pause" : "Play")

            Button {
                HapticFeedback.light.trigger()
                Task { try? await playerService?.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(contentColor)
                    .cassetteGlassButton(size: 56, tint: glassTint)
            }
            .disabled(!isPlaybackAvailable)
            .accessibilityLabel("Skip to next")
        }
    }
}

// MARK: - Bottom toolbar

private struct BottomToolbar: View {
    @Binding var showLyrics: Bool
    @Binding var showQueue: Bool
    let secondaryContentColor: Color
    let glassTint: Color

    var body: some View {
        HStack(spacing: CassetteSpacing.xxxxl) {
            Button { showLyrics = true } label: {
                Image(systemName: "quote.bubble")
                    .font(.title3)
                    .foregroundStyle(secondaryContentColor)
                    .cassetteGlassButton(size: 44, tint: glassTint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Lyrics")

            AirPlayRouteButton(tintColor: secondaryContentColor)
                .frame(width: 44, height: 44)

            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(secondaryContentColor)
                    .cassetteGlassButton(size: 44, tint: glassTint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Queue")
        }
    }
}

#if canImport(UIKit)
private struct AirPlayRouteButton: UIViewRepresentable {
    var tintColor: Color = Color.white.opacity(0.7)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = UIColor(Color.cassetteAccent)
        view.tintColor = UIColor(tintColor)
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = UIColor(tintColor)
    }
}
#else
private struct AirPlayRouteButton: View {
    var tintColor: Color = Color.white.opacity(0.7)

    var body: some View {
        Image(systemName: "airplay.audio")
            .font(.title3)
            .foregroundStyle(tintColor)
            .frame(width: 44, height: 44)
    }
}
#endif

// MARK: - Volume

private struct VolumeSection: View {
    let contentColor: Color
    let secondaryContentColor: Color

    var body: some View {
        #if os(iOS)
        HStack(spacing: CassetteSpacing.m) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(secondaryContentColor)
                .frame(width: 20)
                .accessibilityHidden(true)

            SystemVolumeView(contentColor: contentColor)

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(secondaryContentColor)
                .frame(width: 20)
                .accessibilityHidden(true)
        }
        #endif
    }
}
