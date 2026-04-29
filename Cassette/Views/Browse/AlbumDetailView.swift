// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData

struct AlbumDetailView: View {
    private let albumId: String
    private let initialName: String

    init(album: AlbumID3) {
        albumId = album.id
        initialName = album.name
        let cid = "album:\(album.id)"
        _albumFavoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    init(album: DownloadedAlbum) {
        albumId = album.albumId
        initialName = album.name
        let cid = "album:\(album.albumId)"
        _albumFavoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    init(albumId: String, albumName: String) {
        self.albumId = albumId
        self.initialName = albumName
        let cid = "album:\(albumId)"
        _albumFavoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @State private var viewModel: AlbumDetailViewModel?
    @State private var dominantColor: Color = .clear
    @State private var isLightBackground: Bool = false
    @State private var showDeleteAlert = false
    @State private var artistToNavigate: ArtistID3?
    @Query private var albumFavoriteMatches: [FavoriteRecord]

    private var isAlbumFavorite: Bool { !albumFavoriteMatches.isEmpty }
    private var isOnline: Bool { container?.serverState.isOnline == true }
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
                LoadingStateView()
            }
        }
        .background(
            LinearGradient(
                colors: [
                    (dominantColor == .clear ? Color.cassetteSystemBackground : dominantColor).opacity(0.9),
                    (dominantColor == .clear ? Color.cassetteSystemBackground : dominantColor).opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .cassetteContentWidth()
        .navigationTitle(viewModel?.albumName ?? initialName)
        .navigationBarTitleDisplayModeInline()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticFeedback.light.trigger()
                    Task {
                        if isAlbumFavorite {
                            try? await container?.favoritesService.unstar(itemType: .album, itemId: albumId)
                        } else {
                            try? await container?.favoritesService.star(itemType: .album, itemId: albumId)
                        }
                    }
                } label: {
                    Image(systemName: isAlbumFavorite ? "star.fill" : "star")
                        .foregroundStyle(isAlbumFavorite ? Color.cassetteAccent : .primary)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAlbumFavorite)
                }
                .disabled(!isOnline)
            }
        }
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = AlbumDetailViewModel(
                    albumId: albumId,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    serverState: c.serverState
                )
            }
            await viewModel?.load()
        }
        .task(id: viewModel?.coverArtId) {
            guard let coverArtId = viewModel?.coverArtId else { return }

            let cached = colorExtractor.dominantColor(for: coverArtId, image: nil)
            if cached != .clear {
                dominantColor = cached
                isLightBackground = cached.luminance > 0.6
                return
            }

            await loadDominantColor(coverArtId: coverArtId)
        }
        .navigationDestination(item: $artistToNavigate) { ArtistDetailView(artist: $0) }
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
        withAnimation(.easeIn(duration: 0.5)) {
            dominantColor = color
            isLightBackground = color.luminance > 0.6
        }
    }

    @ViewBuilder
    private func content(_ vm: AlbumDetailViewModel) -> some View {
        if vm.isLoading && vm.songs.isEmpty {
            LoadingStateView()
        } else if let error = vm.error, vm.songs.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Album",
                subtitle: error.displayMessage,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else {
            List {
                albumHeader(vm: vm)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if vm.songs.isEmpty {
                    EmptyStateView(
                        systemImage: "music.note",
                        title: "No Tracks",
                        subtitle: "This album doesn't have any tracks yet."
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                let serverId = container?.serverState.activeServer?.id ?? UUID()
                AlbumSongRows(
                    songs: vm.songs,
                    albumId: albumId,
                    serverId: serverId,
                    downloadingIds: vm.downloadingIds,
                    titleColor: headerTextColor,
                    secondaryColor: headerSecondaryColor,
                    onTap: { index in
                        Task { try? await container?.playerService.play(tracks: vm.songs, startIndex: index) }
                    },
                    onDownload: (vm.isOffline || vm.isDownloadingAlbum) ? nil : { songId in
                        Task { await vm.downloadSong(id: songId) }
                    }
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await vm.load() }
            .alert("Remove downloaded album?", isPresented: $showDeleteAlert) {
                Button("Remove", role: .destructive) { Task { await vm.deleteDownload() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The audio files will be deleted from this device.")
            }
        }
    }

    private func downloadState(for vm: AlbumDetailViewModel) -> AlbumDownloadState {
        let total = vm.songs.count
        guard total > 0 else { return .notDownloaded }
        let downloaded = vm.songs.filter { $0.isDownloaded }.count
        if downloaded == 0 { return .notDownloaded }
        if downloaded == total { return .fullyDownloaded }
        return .partiallyDownloaded(downloaded: downloaded, total: total)
    }

    private func albumHeader(vm: AlbumDetailViewModel) -> some View {
        VStack(spacing: CassetteSpacing.l) {
            CoverArtCard(
                id: vm.coverArtId ?? albumId,
                size: 220,
                cornerRadius: CassetteCornerRadius.large
            )
            .padding(.top, CassetteSpacing.xxl)

            VStack(spacing: CassetteSpacing.s) {
                Text(vm.albumName)
                    .font(.cassetteDetailTitle)
                    .foregroundStyle(headerTextColor)
                    .multilineTextAlignment(.center)
                if let artist = vm.artistName {
                    if let artistId = vm.artistId, !vm.isOffline {
                        Button {
                            Task {
                                guard let c = container,
                                      let fetched = try? await c.libraryService.artist(id: artistId) else { return }
                                artistToNavigate = fetched
                            }
                        } label: {
                            Text(artist)
                                .font(.cassetteCellSubtitle)
                                .foregroundStyle(Color.cassetteAccent)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(artist)
                            .font(.cassetteCellSubtitle)
                            .foregroundStyle(headerSecondaryColor)
                    }
                }
                HStack(spacing: CassetteSpacing.s) {
                    if let year = vm.year { Text(String(year)) }
                    if let genre = vm.genre { Text("·"); Text(genre) }
                    if let format = vm.songs.first?.audioFormat {
                        Text("·")
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .semibold))
                        Text(format.uppercased())
                    }
                }
                .font(.cassetteCaption)
                .foregroundStyle(headerSecondaryColor.opacity(0.8))
            }
            .padding(.horizontal, CassetteSpacing.l)

            HStack(spacing: CassetteSpacing.m) {
                Button {
                    HapticFeedback.medium.trigger()
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
                }, isDisabled: vm.songs.isEmpty || vm.isDownloadingAlbum)
                .frame(maxWidth: 400)

                if !vm.isOffline {
                    if vm.isDownloadingAlbum {
                        Button { Task { await vm.cancelAlbumDownload() } } label: {
                            Image(systemName: "xmark")
                                .font(.cassetteCellTitle)
                                .foregroundStyle(Color.cassetteAccent)
                                .cassetteGlassButton(size: 44)
                        }
                    } else {
                        switch downloadState(for: vm) {
                        case .notDownloaded:
                            Button { Task { await vm.downloadAlbum() } } label: {
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
                            Button {
                                HapticFeedback.heavy.trigger()
                                showDeleteAlert = true
                            } label: {
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

            if vm.isDownloadingAlbum {
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

private nonisolated enum AlbumDownloadState {
    case notDownloaded
    case partiallyDownloaded(downloaded: Int, total: Int)
    case fullyDownloaded
}

// MARK: - Live download indicator rows

/// Sub-view that observes DownloadedTrack changes live via @Query,
/// overriding the isDownloaded flag per row without requiring a VM reload.
private struct AlbumSongRows: View {
    let songs: [DisplayableSong]
    let downloadingIds: Set<String>
    let titleColor: Color
    let secondaryColor: Color
    let onTap: (Int) -> Void
    let onDownload: ((String) -> Void)?

    @Query private var downloadedTracks: [DownloadedTrack]

    init(songs: [DisplayableSong], albumId: String, serverId: UUID, downloadingIds: Set<String> = [], titleColor: Color = .primary, secondaryColor: Color = .secondary, onTap: @escaping (Int) -> Void, onDownload: ((String) -> Void)? = nil) {
        self.songs = songs
        self.downloadingIds = downloadingIds
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.onTap = onTap
        self.onDownload = onDownload
        let aid = albumId
        let sid = serverId
        _downloadedTracks = Query(
            filter: #Predicate<DownloadedTrack> { track in
                track.albumId == aid && track.serverId == sid
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
                coverArtId: song.coverArtId,
                audioFormat: song.audioFormat
            )
            let isDownloading = downloadingIds.contains(song.id)
            let downloadAction: (() -> Void)? = (liveDownloaded || isDownloading) ? nil : onDownload.map { action in { action(song.id) } }
            SongRow(song: liveSong, index: index + 1, titleColor: titleColor, secondaryColor: secondaryColor, onDownload: downloadAction, isDownloading: isDownloading)
                .onTapGesture { onTap(index) }
                .listRowInsets(EdgeInsets(top: 0, leading: CassetteSpacing.l, bottom: 0, trailing: CassetteSpacing.l))
                .listRowBackground(Color.clear)
        }
    }
}
