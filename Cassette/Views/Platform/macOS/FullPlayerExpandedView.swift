// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import AppKit
import OSLog

private enum RightPanel { case lyrics, queue }

struct FullPlayerExpandedView: View {
    @Binding var isPresented: Bool

    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(ArtworkImageCache.self) private var artworkCache
    @Environment(\.openWindow) private var openWindow

    @State private var isScrubbing = false
    @State private var localScrubPosition: Double = 0
    @State private var artworkImage: PlatformImage? = nil
    @State private var isFavorite = false
    @State private var selectedPanel: RightPanel = .queue
    @State private var lyricsViewModel: LyricsViewModel?
    @State private var isMuted = false
    @State private var volumeBeforeMute: Double = 0.7
    @State private var showVolumeSlider = false
    @State private var showAddToPlaylist = false
    @AppStorage("cassette.lastVolume") private var localVolume: Double = 0.7

    private var playerState: PlayerState? { container?.playerState }
    private var currentTrack: DisplayableSong? { playerState?.currentTrack }
    private var isPlaying: Bool { playerState?.playbackState == .playing }
    private var isLoading: Bool { playerState?.playbackState == .loading }
    private var isLiveStream: Bool { playerState?.isLiveStream == true }
    private var noTrack: Bool { currentTrack == nil }
    private var queue: [DisplayableSong] { playerState?.queue ?? [] }
    private var currentIndex: Int { playerState?.currentIndex ?? 0 }
    private var isOnline: Bool { container?.serverState.isOnline == true }

    private var dominantColor: Color {
        colorExtractor.dominantColor(for: currentTrack?.coverArtId, image: artworkImage)
    }

    private var volumeIconName: String {
        if localVolume == 0 || isMuted { return "speaker.slash.fill" }
        if localVolume < 0.33 { return "speaker.fill" }
        if localVolume < 0.66 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    var body: some View {
        ZStack {
            meshGradientBackground
                .ignoresSafeArea()

            GeometryReader { geo in
                contentLayout(geo)
            }
        }
        .overlay(alignment: .topLeading) {
            topLeadingButtons
        }
        .task(id: currentTrack?.id) {
            artworkImage = await artworkCache.load(coverArtId: currentTrack?.coverArtId)
            await refreshFavorite()
        }
        .task(id: currentTrack?.id) {
            guard let track = currentTrack,
                  let serverId = container?.serverState.activeServer?.id,
                  let lyricsService = container?.lyricsService,
                  let pService = container?.playerService,
                  let pState = playerState else {
                lyricsViewModel = nil
                return
            }
            let newVM = LyricsViewModel(
                songId: track.id,
                serverId: serverId,
                lyricsService: lyricsService,
                playerService: pService,
                playerState: pState
            )
            lyricsViewModel = newVM
            await newVM.load()
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showAddToPlaylist) {
            if let track = currentTrack {
                AddToPlaylistSheet(song: track)
                    .environment(artworkCache)
            }
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func contentLayout(_ geo: GeometryProxy) -> some View {
        if geo.size.width >= 900 {
            wideLayout(geo)
        } else {
            narrowLayout(geo)
        }
    }

    private var topLeadingButtons: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Close")

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                    openWindow(id: "mini-player")
                } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Mini Player")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if #available(macOS 26.0, *) {
                    Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .clipShape(Capsule())

            HStack(spacing: 8) {
                AirPlayButton()
                    .frame(width: 20, height: 20)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showVolumeSlider.toggle()
                    }
                } label: {
                    Image(systemName: volumeIconName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)

                if showVolumeSlider {
                    Slider(value: Binding(
                        get: { localVolume },
                        set: { newVal in
                            localVolume = newVal
                            isMuted = newVal == 0
                            Task { await container?.playerService.setVolume(Float(newVal)) }
                        }
                    ), in: 0...1)
                    .frame(width: 80)
                    .tint(.white)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if #available(macOS 26.0, *) {
                    Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, -38)
    }

    private func wideLayout(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            playerColumn(artworkSize: artworkSize(for: geo, isWide: true))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)

            Divider()
                .opacity(0.3)

            rightPanelColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func artworkSize(for geo: GeometryProxy, isWide: Bool) -> CGFloat {
        if isWide {
            let available = geo.size.height - 80
            return max(160, min(300, available - 244))
        } else {
            return max(100, min(260, geo.size.height * 0.55 - 220))
        }
    }

    private func narrowLayout(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            playerColumn(artworkSize: artworkSize(for: geo, isWide: false))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
                .frame(height: geo.size.height * 0.55)

            rightPanelColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Mesh Gradient Background

    private struct ColorPalette {
        let dark: Color
        let mid: Color
        let bright: Color
    }

    private func generatePalette(from base: Color) -> ColorPalette {
        guard base != .clear else {
            return ColorPalette(dark: Color(white: 0.10), mid: Color(white: 0.22), bright: Color(white: 0.38))
        }
        guard let nsBase = NSColor(base).usingColorSpace(.sRGB) else {
            return ColorPalette(dark: base.opacity(0.3), mid: base.opacity(0.6), bright: base.opacity(0.9))
        }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsBase.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let sat = Double(s) * 0.7
        return ColorPalette(
            dark:   Color(hue: Double(h), saturation: sat, brightness: min(max(Double(b) * 0.25, 0.15), 0.20)),
            mid:    Color(hue: Double(h), saturation: sat, brightness: min(max(Double(b) * 0.50, 0.30), 0.35)),
            bright: Color(hue: Double(h), saturation: sat, brightness: min(max(Double(b) * 0.85, 0.50), 0.50))
        )
    }

    private var meshGradientBackground: some View {
        let palette = generatePalette(from: dominantColor)

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12.0) / 12.0)
            let wave  = sin(t * .pi * 2)
            let wave2 = sin(t * .pi * 2 + 1.0)

            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0.0, 0.0),
                    SIMD2<Float>(0.5 + wave  * 0.05, 0.0),
                    SIMD2<Float>(1.0, 0.0),

                    SIMD2<Float>(0.0, 0.5 + wave2 * 0.04),
                    SIMD2<Float>(0.5, 0.5),
                    SIMD2<Float>(1.0, 0.5 - wave2 * 0.04),

                    SIMD2<Float>(0.0, 1.0),
                    SIMD2<Float>(0.5 - wave  * 0.05, 1.0),
                    SIMD2<Float>(1.0, 1.0)
                ],
                colors: [
                    palette.dark,   palette.mid,    palette.dark,
                    palette.mid,    palette.bright, palette.mid,
                    palette.dark,   palette.mid,    palette.dark
                ]
            )
        }
    }

    // MARK: - Player Column

    private func playerColumn(artworkSize: CGFloat = 300) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(maxHeight: 24)

            artworkView(size: artworkSize)
                .padding(.bottom, 28)

            trackInfo
                .padding(.bottom, 20)

            if isLiveStream {
                liveBadge
                    .padding(.bottom, 20)
            } else {
                scrubber
                    .padding(.bottom, 24)
            }

            playbackControls
                .padding(.bottom, 20)

            Spacer()
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func artworkView(size: CGFloat = 300) -> some View {
        let shadowColor = dominantColor == .clear ? Color.black : dominantColor
        ZStack {
            if let track = currentTrack {
                CoverArtView(id: track.coverArtId ?? track.id, size: Int(size))
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 72))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .shadow(color: shadowColor.opacity(0.4), radius: 32, y: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.smooth(duration: 0.3)) { selectedPanel = .lyrics }
        }
    }

    private var trackInfo: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentTrack?.title ?? "")
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(noTrack ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let artist = currentTrack?.artist {
                        Text(artist)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        if let album = currentTrack?.albumName {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(album)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .lineLimit(1)

                if let format = currentTrack?.audioFormat {
                    HStack(spacing: 6) {
                        AudioFormatBadge(format: format, color: .white.opacity(0.7))
                        Text(format)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .white : .white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .disabled(noTrack)

                trackOptionsMenu
            }
        }
        .frame(maxWidth: 340)
    }

    private var trackOptionsMenu: some View {
        Menu {
            Button("Go to Album") { }
            Button("Go to Artist") { }
            Divider()
            Button("Add to Playlist…") { showAddToPlaylist = true }
                .disabled(!isOnline)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(Color.white.opacity(0.8))
        .tint(Color.white)
        .fixedSize()
        .disabled(noTrack)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            ProgressSlider(
                value: Binding(
                    get: { isScrubbing ? localScrubPosition : (playerState?.position ?? 0) },
                    set: { localScrubPosition = $0 }
                ),
                total: max(1, playerState?.duration ?? 1),
                onEditingChanged: { editing in
                    if editing { localScrubPosition = playerState?.position ?? 0 }
                    isScrubbing = editing
                    if !editing {
                        let pos = localScrubPosition
                        Task { await container?.playerService.seek(to: pos) }
                    }
                },
                trackColor: .white.opacity(0.15),
                fillColor: .white
            )
            .disabled(noTrack)

            HStack {
                Text(timeString(isScrubbing ? localScrubPosition : (playerState?.position ?? 0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeString(playerState?.duration ?? 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 340)
    }

    private var liveBadge: some View {
        Text("LIVE")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.red.opacity(0.15), in: Capsule())
    }

    private var playbackControls: some View {
        HStack(spacing: 32) {
            Button {
                Task { await container?.playerService.toggleShuffle() }
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(playerState?.isShuffled == true ? CassetteColors.accentForeground(on: dominantColor) : Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(noTrack)

            Button {
                Task { try? await container?.playerService.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .foregroundStyle(noTrack ? .quaternary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)

            expandedPlayPauseButton

            Button {
                Task { try? await container?.playerService.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .foregroundStyle(noTrack ? .quaternary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)

            Button {
                Task {
                    if let mode = playerState?.repeatMode {
                        await container?.playerService.setRepeatMode(mode.next)
                    }
                }
            } label: {
                Image(systemName: playerState?.repeatMode.systemImage ?? "repeat")
                    .foregroundStyle(playerState?.repeatMode != .off ? CassetteColors.accentForeground(on: dominantColor) : Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(noTrack)
        }
        .font(.title2)
    }

    @ViewBuilder
    private var expandedPlayPauseButton: some View {
        if isLoading {
            ProgressView()
                .frame(width: 52, height: 52)
        } else {
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
                    .font(.system(size: 38))
                    .foregroundStyle(noTrack ? .secondary : .primary)
                    .frame(width: 52, height: 52)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(noTrack)
        }
    }

    // MARK: - Right Panel

    private var rightPanelColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedPanel == .lyrics ? "Lyrics" : "Up Next")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if selectedPanel == .queue, let ps = playerState {
                    let isAutoExtend = ps.isAutoExtendEnabled
                    Button {
                        Task { await container?.playerService.setAutoExtendEnabled(!isAutoExtend) }
                    } label: {
                        Image(systemName: "infinity")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isAutoExtend ? CassetteColors.accentForeground(on: dominantColor) : Color.white.opacity(0.6))
                            .padding(6)
                            .background(isAutoExtend ? CassetteColors.accentBackground : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Auto-extend with Smart Shuffle")
                    .accessibilityValue(isAutoExtend ? "Enabled" : "Disabled")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .opacity(0.3)

            Group {
                switch selectedPanel {
                case .lyrics:
                    if let lyricsVM = lyricsViewModel {
                        LyricsView(viewModel: lyricsVM)
                    } else {
                        ContentUnavailableView("No lyrics available", systemImage: "quote.bubble")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .queue:
                    queueContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .opacity(0.3)

            HStack(spacing: 24) {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { selectedPanel = .lyrics }
                } label: {
                    Image(systemName: "quote.bubble")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(selectedPanel == .lyrics ? CassetteColors.accentBackground : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(noTrack || isLiveStream)

                Button {
                    withAnimation(.smooth(duration: 0.3)) { selectedPanel = .queue }
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(selectedPanel == .queue ? CassetteColors.accentBackground : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 14))
            .padding(16)

            Color.clear.frame(height: 12)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var queueContent: some View {
        let upNext = Array(queue.dropFirst(currentIndex + 1))

        if queue.isEmpty {
            ContentUnavailableView("No tracks in queue", systemImage: "list.bullet.indent")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if let current = currentTrack {
                    Section("Now Playing") {
                        ExpandedQueueRow(track: current, isCurrent: true)
                    }
                }

                if !upNext.isEmpty {
                    Section("Up Next") {
                        ForEach(Array(upNext.enumerated()), id: \.element.id) { offset, track in
                            let absoluteIndex = currentIndex + 1 + offset
                            ExpandedQueueRow(track: track, isCurrent: false)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { try? await container?.playerService.play(tracks: queue, startIndex: absoluteIndex) }
                                }
                        }
                        .onMove { indexSet, destination in
                            guard let relativeSource = indexSet.first else { return }
                            let absoluteSource = currentIndex + 1 + relativeSource
                            let absoluteDestination = currentIndex + 1 + destination
                            Task { await container?.playerService.moveInQueue(fromIndex: absoluteSource, toIndex: absoluteDestination) }
                        }
                        .onDelete { indexSet in
                            let absoluteIndices = indexSet.sorted(by: >).map { currentIndex + 1 + $0 }
                            Task {
                                for absoluteIndex in absoluteIndices {
                                    await container?.playerService.removeFromQueue(at: absoluteIndex)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Helpers

    private func timeString(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func refreshFavorite() async {
        guard let track = currentTrack, let container else {
            isFavorite = false
            return
        }
        isFavorite = container.favoritesService.isFavorite(itemType: .song, itemId: track.id)
    }

    private func toggleFavorite() async {
        guard let track = currentTrack, let container else { return }
        do {
            if isFavorite {
                try await container.favoritesService.unstar(itemType: .song, itemId: track.id)
            } else {
                try await container.favoritesService.star(itemType: .song, itemId: track.id)
            }
            isFavorite.toggle()
        } catch {
            Logger.ui.error("FullPlayerExpandedView: toggleFavorite failed — \(error)")
        }
    }
}

// MARK: - Queue Row

private struct ExpandedQueueRow: View {
    let track: DisplayableSong
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(id: track.coverArtId ?? track.id, size: 36)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.white : .primary)
                    .lineLimit(1)
                if let artist = track.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer()

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
