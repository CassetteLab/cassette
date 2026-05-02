// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI

struct BottomPlayerBar: View {
    @Environment(\.appContainer) private var container

    @State private var isScrubbing = false
    @State private var localScrubPosition: Double? = nil
    @State private var artworkIsHovered = false
    @State private var showQueue = false
    @State private var isFavorite = false
    @State private var localVolume: Double = 0.7

    private var playerState: PlayerState? { container?.playerState }
    private var currentTrack: DisplayableSong? { playerState?.currentTrack }
    private var isPlaying: Bool { playerState?.playbackState == .playing }
    private var isLoading: Bool { playerState?.playbackState == .loading }
    private var isLiveStream: Bool { playerState?.isLiveStream == true }
    private var noTrack: Bool { currentTrack == nil }

    private var progressFraction: Double {
        let position = isScrubbing ? (localScrubPosition ?? 0) : (playerState?.position ?? 0)
        let duration = playerState?.duration ?? 0
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    private var volumeIconName: String {
        if localVolume < 0.01 { return "speaker.slash.fill" }
        if localVolume < 0.4 { return "speaker.fill" }
        return "speaker.wave.2.fill"
    }

    private var artistAlbumLine: String {
        let parts = [currentTrack?.artist, currentTrack?.albumName].compactMap { $0 }
        return parts.isEmpty ? " " : parts.joined(separator: " — ")
    }

    var body: some View {
        HStack(spacing: 0) {
            playbackControls
                .padding(.horizontal, 16)

            currentTrackInfo
                .frame(width: 280)
                .padding(.horizontal, 12)

            scrubberAndSecondaryArea
                .frame(maxWidth: .infinity)
        }
        .frame(height: 56)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 2)
        .task(id: currentTrack?.id) {
            await refreshFavorite()
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 8) {
            Button {
                Task { await container?.playerService.toggleShuffle() }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 12))
                    .foregroundStyle(playerState?.isShuffled == true ? Color.cassetteAccent : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)

            Button {
                Task { try? await container?.playerService.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(noTrack ? .quaternary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)

            playPauseButton

            Button {
                Task { try? await container?.playerService.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
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
                    .font(.system(size: 12))
                    .foregroundStyle(playerState?.repeatMode != .off ? Color.cassetteAccent : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)
        }
    }

    @ViewBuilder
    private var playPauseButton: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 32, height: 32)
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
                    .font(.system(size: 22))
                    .foregroundStyle(noTrack ? .secondary : .primary)
                    .frame(width: 32, height: 32)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(noTrack)
        }
    }

    // MARK: - Track Info

    private var currentTrackInfo: some View {
        HStack(spacing: 10) {
            artworkThumbnail

            VStack(alignment: .leading, spacing: 1) {
                Text(currentTrack?.title ?? "No track playing")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(noTrack ? .secondary : .primary)
                Text(artistAlbumLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 12))
                        .foregroundStyle(isFavorite ? Color.cassetteAccent : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(noTrack)

                Button { } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(noTrack)
            }
        }
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        Group {
            if let track = currentTrack {
                CoverArtView(id: track.coverArtId ?? track.id, size: 40)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .scaleEffect(artworkIsHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: artworkIsHovered)
        .onHover { hovering in
            artworkIsHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Scrubber + Secondary Controls

    private var scrubberAndSecondaryArea: some View {
        GeometryReader { geo in
            let zoneWidth = geo.size.width

            ZStack(alignment: .leading) {
                // Background capsule + progress fill — carries the drag gesture
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.black.opacity(0.15))

                    if !isLiveStream, progressFraction > 0 {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.cassetteAccent.opacity(0.3))
                            .frame(width: zoneWidth * progressFraction)
                            .clipShape(Capsule())
                    }
                }
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !isLiveStream else { return }
                            let duration = playerState?.duration ?? 0
                            guard duration > 0 else { return }
                            let fraction = max(0, min(1, value.location.x / zoneWidth))
                            localScrubPosition = fraction * duration
                            isScrubbing = true
                        }
                        .onEnded { value in
                            guard !isLiveStream else { return }
                            let duration = playerState?.duration ?? 0
                            guard duration > 0 else { return }
                            let fraction = max(0, min(1, value.location.x / zoneWidth))
                            let pos = fraction * duration
                            Task { await container?.playerService.seek(to: pos) }
                            isScrubbing = false
                            localScrubPosition = nil
                        }
                )

                // Floating icons — on top, handle their own taps independently
                floatingIconsRow
            }
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var floatingIconsRow: some View {
        HStack(spacing: 0) {
            // Lyrics (left anchor)
            Button { } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)

            Spacer()

            // Live badge (centre, radio mode only)
            if isLiveStream {
                Text("LIVE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.15), in: Capsule())

                Spacer()
            }

            // Right cluster: AirPlay · volume · queue
            HStack(spacing: 12) {
                Button { } label: {
                    Image(systemName: "airplayaudio")
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Image(systemName: volumeIconName)
                        .font(.system(size: 11))
                    Slider(value: $localVolume, in: 0...1)
                        .frame(width: 60)
                        .controlSize(.mini)
                }
                .foregroundStyle(.secondary)

                Button {
                    showQueue.toggle()
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .foregroundStyle(showQueue ? Color.cassetteAccent : .primary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showQueue, arrowEdge: .top) {
                    QueueView()
                        .frame(width: 400, height: 600)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.trailing, 12)
        }
    }

    // MARK: - Helpers

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
#endif
