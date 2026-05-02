// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import AppKit

struct FullPlayerExpandedView: View {
    @Binding var isPresented: Bool

    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(ArtworkImageCache.self) private var artworkCache

    @State private var isScrubbing = false
    @State private var localScrubPosition: Double = 0
    @State private var artworkImage: PlatformImage? = nil
    @State private var isFavorite = false

    private var playerState: PlayerState? { container?.playerState }
    private var currentTrack: DisplayableSong? { playerState?.currentTrack }
    private var isPlaying: Bool { playerState?.playbackState == .playing }
    private var isLoading: Bool { playerState?.playbackState == .loading }
    private var isLiveStream: Bool { playerState?.isLiveStream == true }
    private var noTrack: Bool { currentTrack == nil }
    private var queue: [DisplayableSong] { playerState?.queue ?? [] }
    private var currentIndex: Int { playerState?.currentIndex ?? 0 }

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

                queueColumn
                    .frame(width: 380)
                    .padding(.vertical, 24)
                    .padding(.trailing, 24)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { isPresented = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
        .task(id: currentTrack?.id) {
            artworkImage = await artworkCache.load(coverArtId: currentTrack?.coverArtId)
            await refreshFavorite()
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
            return ColorPalette(dark: .black, mid: Color(white: 0.08), bright: Color(white: 0.12))
        }
        guard let nsBase = NSColor(base).usingColorSpace(.sRGB) else {
            return ColorPalette(dark: base.opacity(0.3), mid: base.opacity(0.6), bright: base.opacity(0.9))
        }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsBase.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return ColorPalette(
            dark:   Color(hue: Double(h), saturation: Double(s) * 0.9,           brightness: max(0.05, Double(b) * 0.25)),
            mid:    Color(hue: Double(h), saturation: Double(s),                  brightness: max(0.10, Double(b) * 0.50)),
            bright: Color(hue: Double(h), saturation: max(0.2, Double(s) * 0.8),  brightness: min(0.70, Double(b) * 0.85))
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
            artworkView
                .padding(.bottom, 28)

            trackInfo
                .padding(.bottom, 24)

            if isLiveStream {
                liveBadge
                    .padding(.bottom, 24)
            } else {
                scrubber
                    .padding(.bottom, 24)
            }

            playbackControls
                .padding(.bottom, 20)

            secondaryControls
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
    }

    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(currentTrack?.title ?? "")
                .font(.system(size: 32, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(noTrack ? .secondary : .primary)

            HStack(spacing: 6) {
                if let artist = currentTrack?.artist {
                    Text(artist)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.cassetteAccent)
                    if let album = currentTrack?.albumName {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(album)
                            .font(.system(size: 16))
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
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? localScrubPosition : (playerState?.position ?? 0) },
                    set: { localScrubPosition = $0 }
                ),
                in: 0...max(1, playerState?.duration ?? 1),
                onEditingChanged: { editing in
                    if editing { localScrubPosition = playerState?.position ?? 0 }
                    isScrubbing = editing
                    if !editing {
                        let pos = localScrubPosition
                        Task { await container?.playerService.seek(to: pos) }
                    }
                }
            )
            .tint(Color.cassetteAccent)
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
                    .foregroundStyle(playerState?.isShuffled == true ? Color.cassetteAccent : .secondary)
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
                    .foregroundStyle(playerState?.repeatMode != .off ? Color.cassetteAccent : .secondary)
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

    private var secondaryControls: some View {
        HStack(spacing: 24) {
            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? Color.cassetteAccent : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)

            Button { } label: {
                Image(systemName: "airplayaudio")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 14))
    }

    // MARK: - Queue Column

    private var queueColumn: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up Next")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(queue.count) tracks")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .opacity(0.3)

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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
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
