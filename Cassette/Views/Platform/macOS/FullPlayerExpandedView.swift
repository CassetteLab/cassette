// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import AppKit

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

    var body: some View {
        ZStack {
            meshGradientBackground
                .ignoresSafeArea()

            HStack(spacing: 0) {
                playerColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)

                Divider()
                    .opacity(0.3)

                rightPanelColumn
                    .frame(width: 380)
                    .padding(.vertical, 24)
                    .padding(.leading, 16)
                    .padding(.trailing, 24)
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .cassetteGlassButton(size: 28)
            }
            .buttonStyle(.borderless)
            .padding(20)
            .help("Close")
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                    openWindow(id: "mini-player")
                } label: {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.borderless)
                .help("Mini Player")

                AirPlayButton()
                    .frame(width: 20, height: 20)
                muteButton
            }
            .padding(20)
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
            }
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

    private var playerColumn: some View {
        VStack(spacing: 0) {
            Spacer()

            artworkView
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
    private var artworkView: some View {
        let shadowColor = dominantColor == .clear ? Color.black : dominantColor
        ZStack {
            if let track = currentTrack {
                CoverArtView(id: track.coverArtId ?? track.id, size: 300)
                    .frame(width: 300, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 300, height: 300)
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
                            .foregroundStyle(CassetteColors.accentForeground(on: dominantColor))
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
                        AudioFormatBadge(format: format)
                        Text(format)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(isFavorite ? CassetteColors.accentForeground(on: dominantColor) : .secondary)
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
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
                fillColor: CassetteColors.accentForeground(on: dominantColor)
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
                    .foregroundStyle(playerState?.isShuffled == true ? CassetteColors.accentForeground(on: dominantColor) : .secondary)
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
                    .foregroundStyle(playerState?.repeatMode != .off ? CassetteColors.accentForeground(on: dominantColor) : .secondary)
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

    // MARK: - Mute Button

    private var muteButton: some View {
        Button {
            isMuted.toggle()
            let volume = isMuted ? 0.0 : localVolume
            Task { await container?.playerService.setVolume(Float(volume)) }
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Panel

    private var rightPanelColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedPanel == .lyrics ? "Lyrics" : "Up Next")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if selectedPanel == .queue, let ps = playerState {
                    let (symbol, isActive) = ps.queueIcon
                    if isActive {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.cassetteAccent)
                            .animation(.smooth(duration: 0.2), value: symbol)
                            .accessibilityHidden(true)
                    }
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
                        .foregroundStyle(selectedPanel == .lyrics ? CassetteColors.accentForeground(on: dominantColor) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(noTrack || isLiveStream)

                Button {
                    withAnimation(.smooth(duration: 0.3)) { selectedPanel = .queue }
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(selectedPanel == .queue ? CassetteColors.accentForeground(on: dominantColor) : .secondary)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 14))
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.20))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var queueContent: some View {
        if queue.isEmpty {
            ContentUnavailableView("No tracks in queue", systemImage: "list.bullet.indent")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(queue.enumerated()), id: \.element.id) { index, track in
                    ExpandedQueueRow(track: track, isCurrent: index == currentIndex)
                }
                .onMove { indexSet, destination in
                    Task {
                        for fromIndex in indexSet {
                            await container?.playerService.moveInQueue(fromIndex: fromIndex, toIndex: destination)
                        }
                    }
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet.sorted().reversed() {
                            await container?.playerService.removeFromQueue(at: index)
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
        } catch {}
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
                    .foregroundStyle(isCurrent ? Color.cassetteAccent : .primary)
                    .lineLimit(1)
                if let artist = track.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.cassetteAccent)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
