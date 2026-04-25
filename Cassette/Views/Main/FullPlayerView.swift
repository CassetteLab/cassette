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
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(DominantColorExtractor.self) private var colorExtractor

    @State private var coverImage: PlatformImage?
    @State private var dominantColor: Color = .black
    @State private var showLyrics = false
    @State private var showQueue = false

    var body: some View {
        if let playerState = container?.playerState {
            content(playerState)
                .task(id: playerState.currentTrack?.coverArtId) {
                    await loadCoverAndColor(coverArtId: playerState.currentTrack?.coverArtId)
                }
        }
    }

    private func loadCoverAndColor(coverArtId: String?) async {
        guard let coverArtId else {
            withAnimation(.easeInOut(duration: 0.4)) {
                coverImage = nil
                dominantColor = .black
            }
            return
        }
        let url: URL?
        if let localURL = await container?.downloadService.localCoverArtURL(forId: coverArtId) {
            url = localURL
        } else {
            url = await container?.libraryService.coverArtURL(id: coverArtId, size: 300)
        }
        guard let url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = PlatformImage(data: data) else { return }
        let color = colorExtractor.dominantColor(for: coverArtId, image: image)
        withAnimation(.easeInOut(duration: 0.4)) {
            coverImage = image
            dominantColor = color
        }
    }

    @ViewBuilder
    private func content(_ playerState: PlayerState) -> some View {
        let coverArtId = playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id ?? ""
        let isPlaying = playerState.playbackState == .playing

        ZStack {
            // 1. Blurred cover image fullscreen
            if let coverImage {
                Image(platformImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.3)
                    .blur(radius: 80, opaque: true)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else {
                Color.black.ignoresSafeArea()
            }

            // 2. Dominant color tint at 50%
            dominantColor
                .opacity(0.5)
                .ignoresSafeArea()

            // 3. Subtle dark overlay for text contrast
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, CassetteSpacing.s)

                Spacer(minLength: CassetteSpacing.l)

                // Cover art with scale animation on pause
                CoverArtView(id: coverArtId, size: 300)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
                    .scaleEffect(isPlaying ? 1.0 : 0.92)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isPlaying)
                    .padding(.horizontal, CassetteSpacing.xl)

                Spacer(minLength: CassetteSpacing.l)

                // Asymmetric track info: title/album/artist left, star/menu right
                TrackInfoSection(playerState: playerState, container: container)
                    .padding(.horizontal, CassetteSpacing.l)

                ScrubberView(playerState: playerState, playerService: container?.playerService)
                    .padding(.horizontal, CassetteSpacing.l)
                    .padding(.top, CassetteSpacing.m)
                    .disabled(!playerState.isPlaybackAvailable)
                    .opacity(playerState.isPlaybackAvailable ? 1.0 : 0.4)

                PlaybackControlsView(
                    playerState: playerState,
                    playerService: container?.playerService,
                    isPlaybackAvailable: playerState.isPlaybackAvailable
                )
                .padding(.top, CassetteSpacing.l)

                // Volume
                VolumeSection(playerState: playerState, playerService: container?.playerService)
                    .padding(.horizontal, CassetteSpacing.l)
                    .padding(.top, CassetteSpacing.l)

                // Repeat / shuffle
                HStack(spacing: CassetteSpacing.xxxxl) {
                    Button {
                        Task {
                            let next = playerState.repeatMode.next
                            await container?.playerService.setRepeatMode(next)
                        }
                    } label: {
                        Image(systemName: playerState.repeatMode.systemImage)
                            .font(.title3)
                            .foregroundStyle(playerState.repeatMode == .off ? .white.opacity(0.7) : Color.cassetteAccent)
                            .cassetteGlassButton(size: 44, tint: playerState.repeatMode == .off ? nil : Color.cassetteAccent)
                    }

                    Button {
                        Task { await container?.playerService.toggleShuffle() }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.title3)
                            .foregroundStyle(playerState.isShuffled ? Color.cassetteAccent : .white.opacity(0.7))
                            .cassetteGlassButton(size: 44, tint: playerState.isShuffled ? Color.cassetteAccent : nil)
                    }
                }
                .padding(.top, CassetteSpacing.l)

                BottomToolbar(showLyrics: $showLyrics, showQueue: $showQueue)
                    .padding(.top, CassetteSpacing.l)

                Spacer(minLength: CassetteSpacing.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cassetteContentWidth()
            .sheet(isPresented: $showLyrics) {
                LyricsView(song: playerState.currentTrack)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
                    .presentationDetents([.large])
            }
        }
    }

    private var topBar: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 36, height: 5)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .cassetteGlassButton(size: 36)
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, CassetteSpacing.l)
        }
    }
}

// MARK: - Track info section (own @Query for reactive favorite state)

private struct TrackInfoSection: View {
    let playerState: PlayerState
    let container: AppContainer?

    @Query private var favoriteMatches: [FavoriteRecord]

    init(playerState: PlayerState, container: AppContainer?) {
        self.playerState = playerState
        self.container = container
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
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if !playerState.isPlaybackAvailable {
                    Label("Reconnect to resume", systemImage: "wifi.slash")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                } else {
                    HStack(spacing: CassetteSpacing.xs) {
                        if let album = playerState.currentTrack?.albumName {
                            Text(album)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.7))
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
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: CassetteSpacing.s) {
                Button {
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
                        .foregroundStyle(isFavorite ? Color.cassetteAccent : .white)
                        .cassetteGlassButton(size: 44)
                }
                .buttonStyle(.borderless)
                .disabled(!isOnline)

                Menu {
                    Button("Go to Album", systemImage: "square.stack") { }
                    Button("Go to Artist", systemImage: "music.mic") { }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .cassetteGlassButton(size: 44)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Scrubber

private struct ScrubberView: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?

    @State private var isDragging = false
    @State private var scrubPosition: TimeInterval = 0

    // Prefer AVPlayer-reported duration; fall back to song metadata to avoid slider clamping to 0..1
    private var effectiveDuration: TimeInterval {
        playerState.duration > 0 ? playerState.duration : (playerState.currentTrack?.duration ?? 1)
    }

    private var displayPosition: TimeInterval {
        isDragging ? scrubPosition : playerState.position
    }

    var body: some View {
        VStack(spacing: CassetteSpacing.xs) {
            ProgressSlider(
                value: displayPosition,
                total: effectiveDuration,
                isDragging: isDragging
            ) { newValue, finished in
                scrubPosition = newValue
                isDragging = !finished
                if finished {
                    Task { await playerService?.seek(to: newValue) }
                }
            }

            HStack {
                Text(Duration.seconds(displayPosition).formatted(.time(pattern: .minuteSecond)))
                    .font(.cassetteCaption)
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
                Spacer()
                Text(Duration.seconds(max(effectiveDuration - displayPosition, 0)).formatted(.time(pattern: .minuteSecond)))
                    .font(.cassetteCaption)
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }
}

private struct ProgressSlider: View {
    let value: TimeInterval
    let total: TimeInterval
    let isDragging: Bool
    let onChange: (TimeInterval, Bool) -> Void

    private let trackHeight: CGFloat = 4
    private let thumbDiameter: CGFloat = 16

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(max(CGFloat(value / total), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let trackW = geo.size.width
            let fillW = trackW * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: isDragging ? trackHeight * 1.5 : trackHeight)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(fillW, 0), height: isDragging ? trackHeight * 1.5 : trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: max(min(fillW - thumbDiameter / 2, trackW - thumbDiameter), 0))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = min(max(gesture.location.x, 0), trackW)
                        onChange(TimeInterval(x / trackW) * total, false)
                    }
                    .onEnded { gesture in
                        let x = min(max(gesture.location.x, 0), trackW)
                        onChange(TimeInterval(x / trackW) * total, true)
                    }
            )
        }
        .frame(height: thumbDiameter)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
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
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                Task { try? await playerService?.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .cassetteGlassButton(size: 56)
            }
            .disabled(!isPlaybackAvailable)

            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
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
                    .foregroundStyle(isPlaybackAvailable ? Color.cassetteAccentText : .white.opacity(0.5))
                    .cassetteGlassButton(size: 80, tint: isPlaybackAvailable ? Color.cassetteAccent : nil)
            }
            .disabled(!isPlaybackAvailable)

            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                Task { try? await playerService?.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .cassetteGlassButton(size: 56)
            }
            .disabled(!isPlaybackAvailable)
        }
    }
}

// MARK: - Bottom toolbar

private struct BottomToolbar: View {
    @Binding var showLyrics: Bool
    @Binding var showQueue: Bool

    var body: some View {
        HStack(spacing: CassetteSpacing.xxxxl) {
            Button { showLyrics = true } label: {
                Image(systemName: "quote.bubble")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .cassetteGlassButton(size: 44)
            }
            .buttonStyle(.borderless)

            AirPlayRouteButton()
                .frame(width: 44, height: 44)

            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .cassetteGlassButton(size: 44)
            }
            .buttonStyle(.borderless)
        }
    }
}

#if canImport(UIKit)
private struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = UIColor(Color.cassetteAccent)
        view.tintColor = UIColor.white.withAlphaComponent(0.7)
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
private struct AirPlayRouteButton: View {
    var body: some View {
        Image(systemName: "airplay.audio")
            .font(.title3)
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 44, height: 44)
    }
}
#endif

// MARK: - Volume

private struct VolumeSection: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20)

            ProgressSlider(
                value: TimeInterval(playerState.volume),
                total: 1,
                isDragging: false
            ) { newValue, finished in
                let vol = Float(newValue)
                Task { await playerService?.setVolume(vol) }
            }

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20)
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
