// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import AVKit

struct BottomPlayerBar: View {
    @Environment(\.appContainer) private var container

    @State private var isScrubbing = false
    @State private var localScrubPosition: Double = 0
    @State private var artworkIsHovered = false
    @State private var showQueue = false
    @State private var showAddToPlaylist = false
    @State private var isFavorite = false
    @State private var isDownloadedLocally = false
    @State private var isMuted = false
    @AppStorage("cassette.lastVolume") private var localVolume: Double = 0.7
    @State private var barWidth: CGFloat = 800

    var onArtworkTap: (() -> Void)? = nil

    private var playerState: PlayerState? { container?.playerState }
    private var currentTrack: DisplayableSong? { playerState?.currentTrack }
    private var isPlaying: Bool { playerState?.playbackState == .playing }
    private var isLoading: Bool { playerState?.playbackState == .loading }
    private var isLiveStream: Bool { playerState?.isLiveStream == true }
    private var noTrack: Bool { currentTrack == nil }
    private var isCompact: Bool { barWidth < 560 }
    private var isNarrow: Bool { barWidth < 400 }
    private var serverId: UUID? { container?.serverState.activeServer?.id }

    private var artistAlbumLine: String {
        let parts = [currentTrack?.artist, currentTrack?.albumName].compactMap { $0 }
        return parts.isEmpty ? " " : parts.joined(separator: " — ")
    }

    var body: some View {
        HStack(spacing: 0) {
            playbackControls
                .padding(.horizontal, 16)

            centerBlock
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)

            if !isCompact {
                secondaryActions
                    .padding(.horizontal, 16)
            }
        }
        .frame(height: 50)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 2)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        .task(id: currentTrack?.id) {
            await refreshFavorite()
            await refreshDownloadState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteToggleQueue)) { _ in
            showQueue.toggle()
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let track = currentTrack {
                AddToPlaylistSheet(song: track)
            }
        }
    }

    // MARK: - Center Block

    @ViewBuilder
    private var centerBlock: some View {
        VStack(spacing: 3) {
            HStack(alignment: .center, spacing: 10) {
                artworkThumbnail

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentTrack?.title ?? "No track playing")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(noTrack ? .secondary : .primary)
                    Text(artistAlbumLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if !noTrack {
                    ellipsisMenu
                }
            }

            if isLiveStream {
                liveIndicator
            } else {
                thinScrubber
            }
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artworkThumbnail: some View {
        Group {
            if let track = currentTrack {
                CoverArtView(id: track.coverArtId ?? track.id, size: 32)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
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
        .onTapGesture { onArtworkTap?() }
    }

    // MARK: - Scrubber

    private var thinScrubber: some View {
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
            trackColor: .primary.opacity(0.12),
            fillColor: .primary,
            height: 8,
            trackHeight: 2
        )
        .disabled(noTrack)
        .accessibilityHidden(true)
    }

    private var liveIndicator: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.red).frame(width: 5, height: 5)
            Text("LIVE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    // MARK: - Ellipsis Menu

    private var ellipsisMenu: some View {
        Menu {
            Button("Go to Album") {
                // TODO(v1.9): wire navigation from mini player
            }
            Button("Go to Artist") {
                // TODO(v1.9): wire navigation from mini player
            }
            Divider()
            Button("Add to Playlist…") {
                showAddToPlaylist = true
            }
            .disabled(noTrack || container?.serverState.isOnline != true)
            Divider()
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                Task { await toggleFavorite() }
            }
            .disabled(noTrack || container?.serverState.isOnline != true)
            Divider()
            // TODO(v1.9): Download requires Song type from library — only remove is available in mini bar
            Button(isDownloadedLocally ? "Remove Download" : "Download") {
                Task { await toggleDownload() }
            }
            .disabled(noTrack || !isDownloadedLocally)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(noTrack)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 8) {
            if !isNarrow {
                Button {
                    Task { await container?.playerService.toggleShuffle() }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12))
                        .foregroundStyle(playerState?.isShuffled == true ? Color.cassetteAccent : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(noTrack)
            }

            Button {
                Task { try? await container?.playerService.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(noTrack ? .quaternary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)

            playPauseButton

            Button {
                Task { try? await container?.playerService.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(noTrack ? .quaternary : .primary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)

            if !isNarrow {
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
    }

    @ViewBuilder
    private var playPauseButton: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 26, height: 26)
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
                    .font(.system(size: 18))
                    .foregroundStyle(noTrack ? .secondary : .primary)
                    .frame(width: 26, height: 26)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(noTrack)
        }
    }

    // MARK: - Secondary Actions

    private var secondaryActions: some View {
        HStack(spacing: 12) {
            Button { } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .buttonStyle(.plain)

            Button {
                showQueue.toggle()
            } label: {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 12))
                    .foregroundStyle(showQueue ? Color.cassetteAccent : .primary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showQueue, arrowEdge: .top) {
                QueueView()
                    .frame(width: 400, height: 600)
            }

            AirPlayButton()
                .frame(width: 20, height: 20)

            Button {
                toggleMute()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .buttonStyle(.plain)
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

    private func refreshDownloadState() async {
        guard let track = currentTrack, let container, let sid = serverId else {
            isDownloadedLocally = false
            return
        }
        isDownloadedLocally = await container.downloadService.isDownloaded(songId: track.id, serverId: sid)
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

    private func toggleDownload() async {
        guard let track = currentTrack, let container, let sid = serverId else { return }
        if isDownloadedLocally {
            try? await container.downloadService.remove(songId: track.id, serverId: sid)
            isDownloadedLocally = false
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        let volume = isMuted ? 0.0 : localVolume
        Task { await container?.playerService.setVolume(Float(volume)) }
    }
}

struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(NSColor.controlAccentColor, for: .active)
        picker.setRoutePickerButtonColor(NSColor.secondaryLabelColor, for: .normal)
        return picker
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        nsView.setRoutePickerButtonColor(NSColor.controlAccentColor, for: .active)
        nsView.setRoutePickerButtonColor(NSColor.secondaryLabelColor, for: .normal)
    }
}
#endif
