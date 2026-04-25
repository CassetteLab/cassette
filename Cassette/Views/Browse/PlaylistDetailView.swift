// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData

struct PlaylistDetailView: View {
    private let playlistId: String
    private let initialName: String

    init(playlist: Playlist) {
        playlistId = playlist.id
        initialName = playlist.name
    }

    init(playlist: DownloadedPlaylist) {
        playlistId = playlist.playlistId
        initialName = playlist.name
    }

    init(playlistId: String, name: String) {
        self.playlistId = playlistId
        self.initialName = name
    }

    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @State private var viewModel: PlaylistDetailViewModel?
    @State private var dominantColor: Color = .clear
    @State private var isLightBackground: Bool = false
    @State private var showDeleteAlert = false

    private var headerTextColor: Color {
        dominantColor == .clear ? .primary : (isLightBackground ? .black : .white)
    }
    private var headerSecondaryColor: Color {
        dominantColor == .clear ? .secondary : (isLightBackground ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            LinearGradient(
                colors: [dominantColor.opacity(0.75), dominantColor.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .cassetteContentWidth()
        .navigationTitle(viewModel?.name ?? initialName)
        .navigationBarTitleDisplayModeInline()
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = PlaylistDetailViewModel(
                    playlistId: playlistId,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    serverState: c.serverState
                )
            }
            await viewModel?.load()
        }
        .task(id: viewModel?.coverArtId) {
            guard let coverArtId = viewModel?.coverArtId else { return }
            await loadDominantColor(coverArtId: coverArtId)
        }
    }

    private func loadDominantColor(coverArtId: String) async {
        if let localURL = await container?.downloadService.localCoverArtURL(forId: coverArtId) {
            await extractAndSetColor(coverArtId: coverArtId, from: localURL)
            return
        }
        guard let url = await container?.libraryService.coverArtURL(id: coverArtId, size: 100) else { return }
        await extractAndSetColor(coverArtId: coverArtId, from: url)
    }

    private func extractAndSetColor(coverArtId: String, from url: URL) async {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = PlatformImage(data: data) else { return }
        let color = colorExtractor.dominantColor(for: coverArtId, image: image)
        let luminance = computeLuminance(of: color)
        withAnimation(.easeIn(duration: 0.5)) {
            dominantColor = color
            isLightBackground = luminance > 0.6
        }
    }

    private func computeLuminance(of color: Color) -> Double {
        guard let components = color.cgColor?.components, components.count >= 3 else { return 0.5 }
        return 0.299 * Double(components[0]) + 0.587 * Double(components[1]) + 0.114 * Double(components[2])
    }

    @ViewBuilder
    private func content(_ vm: PlaylistDetailViewModel) -> some View {
        if vm.isLoading && vm.songs.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error, vm.songs.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Playlist",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else {
            List {
                playlistHeader(vm: vm)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                let serverId = container?.serverState.activeServer?.id ?? UUID()
                PlaylistSongRows(
                    songs: vm.songs,
                    serverId: serverId,
                    downloadingIds: vm.downloadingIds,
                    onTap: { index in
                        Task { try? await container?.playerService.play(tracks: vm.songs, startIndex: index) }
                    },
                    onDownload: (vm.isOffline || vm.isDownloadingPlaylist) ? nil : { songId in
                        Task { await vm.downloadSong(id: songId) }
                    }
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await vm.load() }
            .alert("Remove downloaded playlist?", isPresented: $showDeleteAlert) {
                Button("Remove", role: .destructive) { Task { await vm.deleteDownload() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The audio files will be deleted from this device.")
            }
        }
    }

    private func downloadState(for vm: PlaylistDetailViewModel) -> PlaylistDownloadState {
        let total = vm.songs.count
        guard total > 0 else { return .notDownloaded }
        let downloaded = vm.songs.filter { $0.isDownloaded }.count
        if downloaded == 0 { return .notDownloaded }
        if downloaded == total { return .fullyDownloaded }
        return .partiallyDownloaded(downloaded: downloaded, total: total)
    }

    private func playlistHeader(vm: PlaylistDetailViewModel) -> some View {
        VStack(spacing: CassetteSpacing.l) {
            CoverArtCard(
                id: vm.coverArtId ?? playlistId,
                size: 220,
                cornerRadius: CassetteCornerRadius.large
            )
            .padding(.top, CassetteSpacing.xxl)

            VStack(spacing: CassetteSpacing.s) {
                Text(vm.name)
                    .font(.cassetteDetailTitle)
                    .foregroundStyle(headerTextColor)
                    .multilineTextAlignment(.center)
                if let owner = vm.owner {
                    Text("by \(owner)")
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(headerSecondaryColor)
                }
                Text("\(vm.songs.count) track\(vm.songs.count == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(headerSecondaryColor.opacity(0.8))
            }
            .padding(.horizontal, CassetteSpacing.l)

            HStack(spacing: CassetteSpacing.m) {
                Button {
                    Task {
                        let shuffled = vm.songs.shuffled()
                        try? await container?.playerService.play(tracks: shuffled, startIndex: 0)
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.cassetteCellTitle)
                        .foregroundStyle(Color.cassetteAccent)
                        .cassetteGlassButton(size: 44)
                }
                .disabled(vm.songs.isEmpty)

                PlayButton(action: {
                    Task { try? await container?.playerService.play(tracks: vm.songs, startIndex: 0) }
                }, isDisabled: vm.songs.isEmpty || vm.isDownloadingPlaylist)
                .frame(maxWidth: 400)

                if !vm.isOffline {
                    if vm.isDownloadingPlaylist {
                        Button { Task { await vm.cancelPlaylistDownload() } } label: {
                            Image(systemName: "xmark")
                                .font(.cassetteCellTitle)
                                .foregroundStyle(Color.cassetteAccent)
                                .cassetteGlassButton(size: 44)
                        }
                    } else {
                        switch downloadState(for: vm) {
                        case .notDownloaded:
                            Button { Task { await vm.downloadPlaylist() } } label: {
                                Image(systemName: "arrow.down.circle")
                                    .font(.cassetteCellTitle)
                                    .foregroundStyle(Color.cassetteAccent)
                                    .cassetteGlassButton(size: 44)
                            }
                            .disabled(vm.songs.isEmpty)
                        case .partiallyDownloaded:
                            Button { Task { await vm.downloadMissingTracks() } } label: {
                                Image(systemName: "arrow.down.circle.dotted")
                                    .font(.cassetteCellTitle)
                                    .foregroundStyle(Color.cassetteAccent)
                                    .cassetteGlassButton(size: 44)
                            }
                        case .fullyDownloaded:
                            Button { showDeleteAlert = true } label: {
                                Image(systemName: "trash")
                                    .font(.cassetteCellTitle)
                                    .foregroundStyle(Color.cassetteAccent)
                                    .cassetteGlassButton(size: 44)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, CassetteSpacing.xxxl)

            if vm.isDownloadingPlaylist {
                HStack(spacing: CassetteSpacing.s) {
                    ProgressView().scaleEffect(0.8)
                    Text("Downloading…")
                        .font(.cassetteCaption)
                        .foregroundStyle(headerSecondaryColor)
                }
            } else if case .partiallyDownloaded(let downloaded, let total) = downloadState(for: vm) {
                Text("\(downloaded)/\(total) tracks downloaded")
                    .font(.cassetteCaption)
                    .foregroundStyle(headerSecondaryColor)
            }
        }
        .padding(.bottom, CassetteSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Download state

private nonisolated enum PlaylistDownloadState {
    case notDownloaded
    case partiallyDownloaded(downloaded: Int, total: Int)
    case fullyDownloaded
}

// MARK: - Live download indicator rows

/// Sub-view that observes DownloadedTrack changes live via @Query,
/// overriding the isDownloaded flag per row without requiring a VM reload.
private struct PlaylistSongRows: View {
    let songs: [DisplayableSong]
    let downloadingIds: Set<String>
    let onTap: (Int) -> Void
    let onDownload: ((String) -> Void)?

    @Query private var downloadedTracks: [DownloadedTrack]

    init(songs: [DisplayableSong], serverId: UUID, downloadingIds: Set<String> = [], onTap: @escaping (Int) -> Void, onDownload: ((String) -> Void)? = nil) {
        self.songs = songs
        self.downloadingIds = downloadingIds
        self.onTap = onTap
        self.onDownload = onDownload
        let sid = serverId
        _downloadedTracks = Query(
            filter: #Predicate<DownloadedTrack> { track in
                track.serverId == sid
            }
        )
    }

    private var downloadedSongIds: Set<String> {
        Set(downloadedTracks.map(\.songId))
    }

    var body: some View {
        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
            let liveDownloaded = downloadedSongIds.contains(song.id)
            let liveSong = DisplayableSong(
                id: song.id,
                title: song.title,
                artist: song.artist,
                albumName: song.albumName,
                duration: song.duration,
                trackNumber: song.trackNumber,
                isDownloaded: liveDownloaded,
                coverArtId: song.coverArtId
            )
            let isDownloading = downloadingIds.contains(song.id)
            let downloadAction: (() -> Void)? = (liveDownloaded || isDownloading) ? nil : onDownload.map { action in { action(song.id) } }
            SongRow(song: liveSong, index: index + 1, showCoverArt: true, onDownload: downloadAction, isDownloading: isDownloading)
                .contentShape(Rectangle())
                .onTapGesture { onTap(index) }
                .listRowBackground(Color.clear)
        }
    }
}
