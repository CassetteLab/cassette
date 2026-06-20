// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic
import OSLog

#if canImport(UIKit)
import AVKit
#endif

private enum PlayerSurface { case player, queue }

struct FullPlayerView: View {
    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var vm = FullPlayerViewModel()
    @State private var showLyrics = false
    @State private var surface: PlayerSurface = .player
    @State private var lyricsViewModel: LyricsViewModel?

    var body: some View {
        if let playerState = container?.playerState {
            content(playerState)
                .task(id: playerState.currentTrack?.coverArtId) {
                    await vm.updateColors(for: playerState.currentTrack?.coverArtId, colorExtractor: colorExtractor, container: container)
                }
                .task(id: playerState.currentTrack?.id) {
                    guard let track = playerState.currentTrack,
                          let serverId = container?.serverState.activeServer?.id,
                          let lyricsService = container?.lyricsService,
                          let playerService = container?.playerService else {
                        lyricsViewModel = nil
                        return
                    }
                    let newVM = LyricsViewModel(
                        songId: track.id,
                        serverId: serverId,
                        lyricsService: lyricsService,
                        playerService: playerService,
                        playerState: playerState
                    )
                    lyricsViewModel = newVM
                    await newVM.load()
                }
        }
    }

    @ViewBuilder
    private func content(_ playerState: PlayerState) -> some View {
        let coverArtId = playerState.isLiveStream
            ? (playerState.currentRadio?.coverArt ?? "")
            : (playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id ?? "")
        let isPlaying = playerState.playbackState == .playing

        VStack(spacing: 0) {
            topBar
                .padding(.top, CassetteSpacing.s)

            Group {
                if surface == .queue && !playerState.isLiveStream {
                    queueSurface(playerState, coverArtId: coverArtId)
                } else {
                    // Live streams have no queue; fall back to the player so the user is never stranded
                    // in a queue surface whose toggle button is hidden.
                    playerSurface(playerState, coverArtId: coverArtId, isPlaying: isPlaying)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cassetteContentWidth()
        .safeAreaInset(edge: .bottom) {
            sharedFooter(playerState)
        }
        .environment(\.cassettePlayingAccent, CassetteColors.accentForeground(on: vm.dominantColor))
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
    }

    // MARK: - Surfaces

    /// Player state: centered album art (or lyrics) + track info. The transport chrome lives in the
    /// shared footer (anchored), so only this region differs between player and queue.
    @ViewBuilder
    private func playerSurface(_ playerState: PlayerState, coverArtId: String, isPlaying: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: CassetteSpacing.l)

            ZStack {
                if showLyrics, let lyricsVM = lyricsViewModel {
                    LyricsView(viewModel: lyricsVM)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.1),
                                    .init(color: .black, location: 0.8),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .transition(.opacity)
                } else {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 280)
                        .overlay {
                            CoverArtView(id: coverArtId, size: 600)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
                        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
                        .scaleEffect(isPlaying ? 1.0 : 0.92)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isPlaying)
                        .onTapGesture {
                            withAnimation(.smooth(duration: 0.3)) { showLyrics = true }
                        }
                        .transition(.opacity)
                        .trackSkipSwipe(playerState: playerState)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.3), value: showLyrics)

            Spacer(minLength: CassetteSpacing.m)

            TrackInfoSection(
                playerState: playerState,
                container: container,
                contentColor: vm.contentColor,
                secondaryContentColor: vm.secondaryContentColor,
                glassTint: vm.glassTint
            )
            .padding(.horizontal, CassetteSpacing.l)

            Spacer(minLength: CassetteSpacing.xs)
        }
    }

    /// Queue state: fixed header (collapsed art + info + pills + Up Next header) over the scrollable
    /// re-housed reorder list, with a status line above the shared footer.
    @ViewBuilder
    private func queueSurface(_ playerState: PlayerState, coverArtId: String) -> some View {
        VStack(spacing: 0) {
            collapsedTrackHeader(playerState, coverArtId: coverArtId)
                .padding(.horizontal, CassetteSpacing.l)
                .padding(.top, CassetteSpacing.s)

            queuePills(playerState)
                .padding(.horizontal, CassetteSpacing.l)
                .padding(.vertical, CassetteSpacing.m)

            upNextHeader(playerState)
                .padding(.horizontal, CassetteSpacing.l)
                .padding(.bottom, CassetteSpacing.xs)

            InlineQueueList(playerState: playerState)
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)

            queueStatusLine(playerState)
                .padding(.horizontal, CassetteSpacing.l)
                .padding(.vertical, CassetteSpacing.s)
        }
    }

    private func collapsedTrackHeader(_ playerState: PlayerState, coverArtId: String) -> some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtView(id: coverArtId, size: 120)
                .frame(width: 56, height: 56)
                .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)

            TrackInfoSection(
                playerState: playerState,
                container: container,
                contentColor: vm.contentColor,
                secondaryContentColor: vm.secondaryContentColor,
                glassTint: vm.glassTint,
                compact: true
            )
        }
    }

    private func queuePills(_ playerState: PlayerState) -> some View {
        HStack(spacing: CassetteSpacing.s) {
            queuePill(systemImage: "shuffle", isActive: playerState.isShuffled,
                      label: playerState.isShuffled ? "Shuffle On" : "Shuffle Off") {
                Task { await container?.playerService.toggleShuffle() }
            }
            queuePill(systemImage: playerState.repeatMode.systemImage, isActive: playerState.repeatMode != .off,
                      label: "Repeat") {
                Task { await container?.playerService.setRepeatMode(playerState.repeatMode.next) }
            }
            queuePill(systemImage: "infinity", isActive: playerState.isAutoExtendEnabled,
                      label: "Auto-extend with Smart Shuffle") {
                Task { await container?.playerService.setAutoExtendEnabled(!playerState.isAutoExtendEnabled) }
            }
        }
    }

    private func queuePill(systemImage: String, isActive: Bool, label: String, action: @escaping () -> Void) -> some View {
        let accent = CassetteColors.accentForeground(on: vm.dominantColor)
        return Button {
            HapticFeedback.light.trigger()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(isActive ? Color.white : vm.secondaryContentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CassetteSpacing.s)
                .background {
                    Capsule().fill(isActive ? accent : Color.white.opacity(0.1))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func upNextHeader(_ playerState: PlayerState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Up Next")
                .font(.cassetteSectionTitle)
                .foregroundStyle(vm.contentColor)
            if let album = playerState.currentTrack?.albumName, !album.isEmpty {
                Text(album)
                    .font(.cassetteCaption)
                    .foregroundStyle(vm.secondaryContentColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func queueStatusLine(_ playerState: PlayerState) -> some View {
        let upNextCount = max(playerState.queue.count - playerState.currentIndex - 1, 0)
        var bits: [String] = ["\(upNextCount) up next"]
        if playerState.repeatMode == .all {
            bits.append("Repeating all")
        } else if playerState.repeatMode == .one {
            bits.append("Repeating one")
        }
        if playerState.isShuffled { bits.append("Shuffled") }
        if playerState.isAutoExtendEnabled { bits.append("Auto-extend on") }
        return Text(bits.joined(separator: " · "))
            .font(.cassetteCaption)
            .foregroundStyle(vm.secondaryContentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
    }

    /// Scrubber + transport + volume + bottom toolbar — one instance anchored across both surfaces, so
    /// its `@State` / UIKit-backed children are never re-created by the surface toggle.
    @ViewBuilder
    private func sharedFooter(_ playerState: PlayerState) -> some View {
        VStack(spacing: 0) {
            if !playerState.isLiveStream {
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
            }

            PlaybackControlsView(
                playerState: playerState,
                playerService: container?.playerService,
                isPlaybackAvailable: playerState.isPlaybackAvailable,
                contentColor: vm.contentColor,
                secondaryContentColor: vm.secondaryContentColor
            )
            .padding(.top, CassetteSpacing.s)

            if dynamicTypeSize < .accessibility1 {
                VolumeSection(contentColor: vm.contentColor, secondaryContentColor: vm.secondaryContentColor)
                    .padding(.horizontal, CassetteSpacing.l)
                    .padding(.top, CassetteSpacing.s)
            }

            BottomToolbar(
                showLyrics: $showLyrics,
                surface: $surface,
                isLiveStream: playerState.isLiveStream,
                secondaryContentColor: vm.secondaryContentColor,
                accentColor: CassetteColors.accentForeground(on: vm.dominantColor),
                playerState: playerState
            )
            .padding(.top, CassetteSpacing.s)
        }
    }

    private var topBar: some View {
        Capsule()
            .fill(vm.contentColor.opacity(0.4))
            .frame(width: 36, height: 5)
            .accessibilityHidden(true)
    }

}

// MARK: - Track info section (own @Query for reactive favorite state)

private struct TrackInfoSection: View {
    let playerState: PlayerState
    let container: AppContainer?
    let contentColor: Color
    let secondaryContentColor: Color
    let glassTint: Color
    var compact: Bool = false

    @Query private var favoriteMatches: [FavoriteRecord]
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var songToAddToPlaylist: DisplayableSong?
    @State private var showAlbumSheet = false

    init(playerState: PlayerState, container: AppContainer?, contentColor: Color, secondaryContentColor: Color, glassTint: Color, compact: Bool = false) {
        self.playerState = playerState
        self.container = container
        self.contentColor = contentColor
        self.secondaryContentColor = secondaryContentColor
        self.glassTint = glassTint
        self.compact = compact
        let cid = "song:\(playerState.currentTrack?.id ?? "")"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    private var isFavorite: Bool { !favoriteMatches.isEmpty }
    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        HStack(alignment: .top, spacing: CassetteSpacing.m) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                Text(playerState.isLiveStream ? (playerState.currentRadio?.name ?? "") : (playerState.currentTrack?.title ?? ""))
                    .font(compact ? .cassetteSectionTitle : .title2)
                    .fontWeight(compact ? .semibold : .bold)
                    .foregroundStyle(contentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !playerState.isPlaybackAvailable {
                    Label("Reconnect to resume", systemImage: "wifi.slash")
                        .font(.callout)
                        .foregroundStyle(secondaryContentColor)
                        .lineLimit(1)
                } else if playerState.isLiveStream {
                    Text("Live Radio")
                        .font(.subheadline)
                        .foregroundStyle(secondaryContentColor)
                        .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                        HStack(spacing: CassetteSpacing.xs) {
                            if let artist = playerState.currentTrack?.artist {
                                Button {
                                    goToArtist()
                                } label: {
                                    Text(artist)
                                        .font(.subheadline)
                                        .foregroundStyle(secondaryContentColor)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .buttonStyle(.plain)
                                .disabled(!isOnline)
                            }
                            if let format = playerState.currentTrack?.audioFormat {
                                AudioFormatBadge(format: format, color: secondaryContentColor)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .trackSkipSwipe(playerState: playerState)

            HStack(spacing: CassetteSpacing.s) {
                if !playerState.isLiveStream {
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
                            .foregroundStyle(contentColor)
                            .cassetteGlassButton(size: 44, tint: glassTint)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isOnline)
                    .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }

                Menu {
                    if !playerState.isLiveStream {
                        Button("Go to Album", systemImage: "square.stack") {
                            guard playerState.currentTrack?.albumId != nil else { return }
                            showAlbumSheet = true
                        }
                        .disabled(playerState.currentTrack?.albumId == nil || !isOnline)
                        Button("Go to Artist", systemImage: "music.mic") {
                            goToArtist()
                        }
                        .disabled(playerState.currentTrack?.artist == nil || !isOnline)
                        Divider()
                        Button("Add to Playlist...", systemImage: "music.note.list") {
                            songToAddToPlaylist = playerState.currentTrack
                        }
                        .disabled(!isOnline || playerState.currentTrack == nil)
                        Divider()
                    }
                    Button {
                        Task { await triggerSmartShuffle() }
                    } label: {
                        Label("Smart Shuffle", systemImage: "shuffle.circle")
                    }
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
        .sheet(isPresented: $showAlbumSheet) {
            if let track = playerState.currentTrack,
               let albumId = track.albumId,
               let albumName = track.albumName {
                #if os(macOS)
                AlbumDetailMacOS(albumId: albumId, albumName: albumName, coverArtId: track.coverArtId)
                #else
                NavigationStack {
                    AlbumDetailView(albumId: albumId, albumName: albumName, coverArtId: track.coverArtId)
                }
                #endif
            }
        }
        .sheet(item: $songToAddToPlaylist) { song in
            AddToPlaylistSheet(song: song)
                .environment(artworkImageCache)
        }
    }

    /// Navigates to the current track's artist by routing through the Home stack (via
    /// `.cassetteNavigateToArtist`), mirroring macOS. Prefers the track's own `artistId`;
    /// falls back to a name search only when the track has no artistId (incomplete metadata).
    private func goToArtist() {
        guard let track = playerState.currentTrack else { return }
        if track.artistId != nil {
            postNavigateToArtist(track: track)
            return
        }
        guard let name = track.artist else { return }
        Task {
            guard let c = container,
                  let result = try? await c.libraryService.search(name),
                  let found = result.artist?.first else { return }
            postNavigateToArtist(artistId: found.id, artistName: found.name, coverArtId: found.coverArt)
        }
    }

    private func triggerSmartShuffle() async {
        guard let container else { return }
        do {
            try await container.playerService.playSmartShuffle()
        } catch {
            container.toastService.showError(smartShuffleErrorMessage(from: error))
        }
    }

    private func smartShuffleErrorMessage(from error: Error) -> String {
        if case CassetteError.smartShuffleEmpty = error {
            return "Smart Shuffle unavailable — try playing some tracks first or download more music for offline use."
        }
        return "Smart Shuffle failed. Please try again."
    }
}

// MARK: - Scrubber

private struct ScrubberView: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?
    let contentColor: Color
    let secondaryContentColor: Color

    @State private var isDragging = false
    @State private var isSeeking = false
    @State private var displayPosition: TimeInterval = 0
    @State private var isAdvancing = false

    // Prefer AVPlayer-reported duration; fall back to song metadata to avoid slider clamping to 0..1
    private var effectiveDuration: TimeInterval {
        playerState.duration > 0 ? playerState.duration : (playerState.currentTrack?.duration ?? 1)
    }

    private var shownPosition: TimeInterval {
        (isDragging || isSeeking) ? displayPosition : playerState.position
    }

    // ProgressSlider writes dragged values here; holds the seeked position until AVPlayer confirms.
    private var positionBinding: Binding<TimeInterval> {
        Binding(
            get: { (isDragging || isSeeking) ? displayPosition : playerState.position },
            set: { newValue in displayPosition = newValue }
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
                        isSeeking = true
                        let target = displayPosition
                        Task {
                            defer { isSeeking = false }
                            await playerService?.seek(to: target)
                        }
                    }
                },
                trackColor: contentColor.opacity(0.2),
                fillColor: contentColor.opacity(0.95),
                isInteracting: isDragging || isSeeking,
                isAdvancing: isAdvancing
            )
            .onChange(of: playerState.position) { oldValue, newValue in
                isAdvancing = newValue > oldValue
            }

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
    var height: CGFloat = 32
    var trackHeight: CGFloat = 5
    var isInteracting: Bool = false
    var isAdvancing: Bool = false

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
                    .animation(isDragging || isInteracting || !isAdvancing ? nil : .linear(duration: 0.5), value: value)
            }
            .frame(height: isDragging ? 12 : trackHeight)
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
        .frame(height: height)
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
        return min(totalWidth, max(0, (CGFloat(displayedValue) / CGFloat(total)) * totalWidth))
    }
}

// MARK: - Playback controls

private struct PlaybackControlsView: View {
    let playerState: PlayerState
    let playerService: (any PlayerServiceProtocol)?
    var isPlaybackAvailable: Bool = true
    let contentColor: Color
    let secondaryContentColor: Color

    var body: some View {
        HStack(spacing: CassetteSpacing.xxxxl) {
            if !playerState.isLiveStream {
                Button {
                    HapticFeedback.light.trigger()
                    Task { try? await playerService?.skipToPrevious() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .foregroundStyle(contentColor)
                        .frame(width: 56, height: 56)
                }
                .disabled(!isPlaybackAvailable)
                .accessibilityLabel("Skip to previous")
            }

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
                    .font(.system(size: 44))
                    .foregroundStyle(isPlaybackAvailable ? contentColor : contentColor.opacity(0.4))
                    .frame(width: 80, height: 80)
            }
            .disabled(!isPlaybackAvailable)
            .accessibilityLabel(playerState.playbackState == .playing ? "Pause" : "Play")

            if !playerState.isLiveStream {
                Button {
                    HapticFeedback.light.trigger()
                    Task { try? await playerService?.skipToNext() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .foregroundStyle(contentColor)
                        .frame(width: 56, height: 56)
                }
                .disabled(!isPlaybackAvailable)
                .accessibilityLabel("Skip to next")
            }
        }
    }
}

// MARK: - Bottom toolbar

private struct BottomToolbar: View {
    @Binding var showLyrics: Bool
    @Binding var surface: PlayerSurface
    let isLiveStream: Bool
    let secondaryContentColor: Color
    let accentColor: Color
    let playerState: PlayerState

    var body: some View {
        HStack(spacing: CassetteSpacing.xxxxl) {
            if !isLiveStream {
                Button {
                    if surface == .queue { surface = .player }
                    withAnimation(.smooth(duration: 0.3)) { showLyrics.toggle() }
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.title3)
                        .foregroundStyle(showLyrics && surface == .player ? accentColor : secondaryContentColor)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Lyrics")
            }

            AirPlayRouteButton(tintColor: secondaryContentColor)
                .frame(width: 44, height: 44)

            if !isLiveStream {
                Button {
                    // Phase 1: instant surface toggle (no morph animation).
                    if surface == .queue {
                        surface = .player
                    } else {
                        surface = .queue
                        showLyrics = false
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundStyle(surface == .queue ? accentColor : secondaryContentColor)
                        .overlay(alignment: .topTrailing) {
                            if let badge = playerState.queueModeBadge {
                                Image(systemName: badge)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.cassetteAccent)
                                    .padding(2)
                                    .background(.background, in: Circle())
                                    .overlay(Circle().stroke(.background.opacity(0.5), lineWidth: 0.5))
                                    .offset(x: 6, y: -6)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.smooth(duration: 0.2), value: playerState.queueModeBadge)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Queue")
            }
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
