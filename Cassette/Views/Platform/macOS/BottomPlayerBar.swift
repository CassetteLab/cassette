// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
                .frame(width: 260)
                .padding(.trailing, 8)

            scrubberCenter
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)

            if !isCompact {
                secondaryActions
                    .padding(.horizontal, 16)
            }
        }
        .frame(height: 80)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 2)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        .task(id: currentTrack?.id) {
            await refreshFavorite()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteToggleQueue)) { _ in
            showQueue.toggle()
        }
        .onChange(of: localVolume) { _, newValue in
            Task { await container?.playerService.setVolume(Float(newValue)) }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let track = currentTrack {
                AddToPlaylistSheet(song: track)
            }
        }
    }

    @ViewBuilder
    private var scrubberCenter: some View {
        if isLiveStream {
            Text("LIVE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.red.opacity(0.15), in: Capsule())
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 2) {
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
                    trackColor: .primary.opacity(0.15),
                    fillColor: Color.cassetteAccent
                )
                .disabled(noTrack)

                HStack {
                    Text(timeString(isScrubbing ? localScrubPosition : (playerState?.position ?? 0)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(timeString(playerState?.duration ?? 0))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
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

    private func timeString(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
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
            .onTapGesture { onArtworkTap?() }

            Button {
                Task { await toggleFavorite() }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .foregroundStyle(isFavorite ? Color.cassetteAccent : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(noTrack)
        }
        .contextMenu {
            Button {
                showAddToPlaylist = true
            } label: {
                Label("Add to Playlist...", systemImage: "music.note.list")
            }
            .disabled(noTrack || container?.serverState.isOnline != true)

            Divider()

            Button {
                Task { await toggleFavorite() }
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
            .disabled(noTrack || container?.serverState.isOnline != true)

            Button {
                guard let track = currentTrack else { return }
                let info = "\(track.artist ?? "Unknown Artist") \u{2014} \(track.title)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(info, forType: .string)
            } label: {
                Label("Copy Track Info", systemImage: "doc.on.doc")
            }
            .disabled(noTrack)
            // TODO(v1.5.x): Add "Show in Album" and "Show in Artist" once
            // albumId/artistId are added to DisplayableSong and NavigationPath
            // is lifted into RootViewMacOS.
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
        .onTapGesture { onArtworkTap?() }
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

            RoutePickerView()
                .frame(width: 20, height: 20)

            HStack(spacing: 4) {
                Image(systemName: volumeIconName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ProgressSlider(
                    value: $localVolume,
                    total: 1.0,
                    onEditingChanged: { _ in },
                    trackColor: .primary.opacity(0.15),
                    fillColor: .primary.opacity(0.6),
                    height: 20
                )
                .frame(width: 60)
            }

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

private struct RoutePickerView: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        return view
    }
    func updateNSView(_ view: AVRoutePickerView, context: Context) {}
}
#endif
