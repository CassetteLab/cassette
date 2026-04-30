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
    private let coverArtId: String?
    private let initialDominantColor: Color
    private let initialCoverImage: PlatformImage?
    private let zoomSourceId: String?
    private let zoomNamespace: Namespace.ID?

    init(playlist: Playlist, coverArtId: String? = nil, initialDominantColor: Color = .clear, initialCoverImage: PlatformImage? = nil, zoomSourceId: String? = nil, zoomNamespace: Namespace.ID? = nil) {
        playlistId = playlist.id
        initialName = playlist.name
        self.coverArtId = coverArtId
        self.initialDominantColor = initialDominantColor
        self.initialCoverImage = initialCoverImage
        self.zoomSourceId = zoomSourceId
        self.zoomNamespace = zoomNamespace
        _dominantColor = State(initialValue: initialDominantColor)
        _isLightBackground = State(initialValue: initialDominantColor == .clear ? false : initialDominantColor.luminance > 0.6)
    }

    init(playlist: DownloadedPlaylist, coverArtId: String? = nil, initialDominantColor: Color = .clear, initialCoverImage: PlatformImage? = nil, zoomSourceId: String? = nil, zoomNamespace: Namespace.ID? = nil) {
        playlistId = playlist.playlistId
        initialName = playlist.name
        self.coverArtId = coverArtId
        self.initialDominantColor = initialDominantColor
        self.initialCoverImage = initialCoverImage
        self.zoomSourceId = zoomSourceId
        self.zoomNamespace = zoomNamespace
        _dominantColor = State(initialValue: initialDominantColor)
        _isLightBackground = State(initialValue: initialDominantColor == .clear ? false : initialDominantColor.luminance > 0.6)
    }

    init(playlistId: String, name: String, coverArtId: String? = nil, initialDominantColor: Color = .clear, initialCoverImage: PlatformImage? = nil, zoomSourceId: String? = nil, zoomNamespace: Namespace.ID? = nil) {
        self.playlistId = playlistId
        self.initialName = name
        self.coverArtId = coverArtId
        self.initialDominantColor = initialDominantColor
        self.initialCoverImage = initialCoverImage
        self.zoomSourceId = zoomSourceId
        self.zoomNamespace = zoomNamespace
        _dominantColor = State(initialValue: initialDominantColor)
        _isLightBackground = State(initialValue: initialDominantColor == .clear ? false : initialDominantColor.luminance > 0.6)
    }

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @State private var viewModel: PlaylistDetailViewModel?
    @State private var dominantColor: Color = .clear
    @State private var isLightBackground: Bool = false
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var editSheetDeletedPlaylist = false

    private var headerTextColor: Color {
        dominantColor == .clear ? .primary : (isLightBackground ? .black : .white)
    }
    private var headerSecondaryColor: Color {
        dominantColor == .clear ? .secondary : (isLightBackground ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
    }
    private var isLoadingSkeleton: Bool {
        viewModel == nil || (viewModel?.isLoading == true && viewModel?.songs.isEmpty == true)
    }

    var body: some View {
        // Kept as List to preserve PlaylistSongRows' .onDelete (swipe-to-remove) and .onMove (drag-to-reorder).
        // ScrollView + LazyVStack refactor is deferred until those interactions are re-implemented outside List.
        List {
            playlistHeader(vm: viewModel)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if isLoadingSkeleton {
                skeletonRows
            } else if let vm = viewModel {
                if let error = vm.error, vm.songs.isEmpty {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Playlist",
                        subtitle: error.displayMessage,
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if vm.songs.isEmpty {
                    EmptyStateView(
                        systemImage: "music.note.list",
                        title: "Empty Playlist",
                        subtitle: "This playlist doesn't have any tracks yet."
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    let serverId = container?.serverState.activeServer?.id ?? UUID()
                    PlaylistSongRows(
                        songs: vm.songs,
                        serverId: serverId,
                        downloadingIds: vm.downloadingIds,
                        titleColor: headerTextColor,
                        secondaryColor: headerSecondaryColor,
                        onTap: { index in
                            Task { try? await container?.playerService.play(tracks: vm.songs, startIndex: index) }
                        },
                        onDownload: (vm.isOffline || vm.isDownloadingPlaylist) ? nil : { songId in
                            Task { await vm.downloadSong(id: songId) }
                        },
                        onRemove: vm.isOffline ? nil : { index in
                            Task { await vm.removeTrack(at: index) }
                        },
                        onReorder: vm.isOffline ? nil : { source, destination in
                            Task { await vm.moveTracks(from: source, to: destination) }
                        }
                    )
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel?.load() }
        .alert("Remove downloaded playlist?", isPresented: $showDeleteAlert) {
            Button("Remove", role: .destructive) { Task { await viewModel?.deleteDownload() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The audio files will be deleted from this device.")
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
        .navigationTitle(viewModel?.name ?? initialName)
        .navigationBarTitleDisplayModeInline()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.white)
                }
                .disabled(container?.serverState.isOnline != true || viewModel?.playlistDetail == nil)
            }
        }
        .task {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = PlaylistDetailViewModel(
                    playlistId: playlistId,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    playlistService: c.playlistService,
                    toastService: c.toastService,
                    serverState: c.serverState
                )
            }
            await viewModel?.load()
        }
        .task(id: viewModel?.coverArtId) {
            guard let artId = viewModel?.coverArtId else { return }

            let cached = colorExtractor.dominantColor(for: artId, image: nil)
            if cached != .clear {
                dominantColor = cached
                isLightBackground = cached.luminance > 0.6
                return
            }

            await loadDominantColor(coverArtId: artId)
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            if editSheetDeletedPlaylist {
                dismiss()
            } else {
                Task { await viewModel?.load() }
            }
        }) {
            if let detail = viewModel?.playlistDetail {
                EditPlaylistSheet(
                    playlist: detail,
                    onDeleted: { editSheetDeletedPlaylist = true }
                )
            }
        }
        .modifier(ConditionalZoomTransition(sourceId: zoomSourceId, namespace: zoomNamespace))
    }

    // MARK: - Skeleton rows (list-compatible; kept with listRow modifiers since List is preserved)

    @ViewBuilder
    private var skeletonRows: some View {
        ForEach(0..<5, id: \.self) { _ in
            HStack(spacing: CassetteSpacing.m) {
                SkeletonBlock(width: 20, height: 20, cornerRadius: 4)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 200, height: 16, cornerRadius: 4)
                    SkeletonBlock(width: 140, height: 12, cornerRadius: 4)
                }
                Spacer()
            }
            .padding(.vertical, CassetteSpacing.xs)
            .listRowInsets(EdgeInsets(top: 0, leading: CassetteSpacing.l, bottom: 0, trailing: CassetteSpacing.l))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Color loading

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
        withAnimation(.easeIn(duration: 0.2)) {
            dominantColor = color
            isLightBackground = color.luminance > 0.6
        }
    }

    // MARK: - Download state

    private func downloadState(for vm: PlaylistDetailViewModel) -> PlaylistDownloadState {
        let total = vm.songs.count
        guard total > 0 else { return .notDownloaded }
        let downloaded = vm.songs.filter { $0.isDownloaded }.count
        if downloaded == 0 { return .notDownloaded }
        if downloaded == total { return .fullyDownloaded }
        return .partiallyDownloaded(downloaded: downloaded, total: total)
    }

    // MARK: - Header

    private func playlistHeader(vm: PlaylistDetailViewModel?) -> some View {
        VStack(spacing: CassetteSpacing.l) {
            Group {
                if initialCoverImage == nil && vm?.coverArtId == nil && coverArtId == nil {
                    SkeletonBlock(width: 220, height: 220, cornerRadius: CassetteCornerRadius.large)
                } else {
                    CoverArtCard(
                        id: vm?.coverArtId ?? coverArtId ?? playlistId,
                        size: 220,
                        cornerRadius: CassetteCornerRadius.large,
                        initialImage: initialCoverImage
                    )
                }
            }
            .padding(.top, CassetteSpacing.xxl)

            VStack(spacing: CassetteSpacing.s) {
                Text(vm?.name ?? initialName)
                    .font(.cassetteDetailTitle)
                    .foregroundStyle(headerTextColor)
                    .multilineTextAlignment(.center)
                if vm == nil {
                    SkeletonBlock(width: 140, height: 18, cornerRadius: 4)
                } else if let owner = vm?.owner {
                    Text("by \(owner)")
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(headerSecondaryColor)
                }
                if vm == nil {
                    SkeletonBlock(width: 100, height: 14, cornerRadius: 4)
                } else if let vm {
                    Text("\(vm.songs.count) track\(vm.songs.count == 1 ? "" : "s")")
                        .font(.cassetteCaption)
                        .foregroundStyle(headerSecondaryColor.opacity(0.8))
                }
            }
            .padding(.horizontal, CassetteSpacing.l)

            HStack(spacing: CassetteSpacing.m) {
                Button {
                    HapticFeedback.medium.trigger()
                    Task {
                        let shuffled = vm?.songs.shuffled() ?? []
                        guard !shuffled.isEmpty else { return }
                        try? await container?.playerService.play(tracks: shuffled, startIndex: 0)
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.cassetteCellTitle)
                        .foregroundStyle(Color.cassetteAccent)
                        .cassetteGlassButton(size: 44)
                }
                .disabled(vm?.songs.isEmpty != false)
                .opacity(vm == nil ? 0.4 : 1)

                PlayButton(action: {
                    Task {
                        guard let songs = vm?.songs, !songs.isEmpty else { return }
                        try? await container?.playerService.play(tracks: songs, startIndex: 0)
                    }
                }, isDisabled: (vm?.songs.isEmpty == true) || (vm?.isDownloadingPlaylist == true))
                .frame(maxWidth: 400)

                if vm?.isOffline != true {
                    if let vm {
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
                    } else {
                        Button { } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.cassetteCellTitle)
                                .foregroundStyle(Color.cassetteAccent)
                                .cassetteGlassButton(size: 44)
                        }
                        .disabled(true)
                        .opacity(0.4)
                    }
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, CassetteSpacing.xxxl)

            if let vm {
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
    let titleColor: Color
    let secondaryColor: Color
    let onTap: (Int) -> Void
    let onDownload: ((String) -> Void)?
    let onRemove: ((Int) -> Void)?
    let onReorder: ((IndexSet, Int) -> Void)?

    @Query private var downloadedTracks: [DownloadedTrack]

    init(songs: [DisplayableSong], serverId: UUID, downloadingIds: Set<String> = [], titleColor: Color = .primary, secondaryColor: Color = .secondary, onTap: @escaping (Int) -> Void, onDownload: ((String) -> Void)? = nil, onRemove: ((Int) -> Void)? = nil, onReorder: ((IndexSet, Int) -> Void)? = nil) {
        self.songs = songs
        self.downloadingIds = downloadingIds
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.onTap = onTap
        self.onDownload = onDownload
        self.onRemove = onRemove
        self.onReorder = onReorder
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
        if let removeAction = onRemove {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                makeRow(index: index, song: song)
            }
            .onDelete { indexSet in
                for index in indexSet.sorted(by: >) { removeAction(index) }
            }
            .onMove { source, destination in
                onReorder?(source, destination)
            }
        } else {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                makeRow(index: index, song: song)
            }
        }
    }

    @ViewBuilder
    private func makeRow(index: Int, song: DisplayableSong) -> some View {
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
        SongRow(song: liveSong, index: index + 1, showCoverArt: true, titleColor: titleColor, secondaryColor: secondaryColor, onDownload: downloadAction, isDownloading: isDownloading)
            .contentShape(Rectangle())
            .onTapGesture { onTap(index) }
            .listRowBackground(Color.clear)
    }
}

// MARK: - Zoom transition modifier

private struct ConditionalZoomTransition: ViewModifier {
    let sourceId: String?
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let sourceId, let namespace {
            if #available(macOS 15.0, *) {
                content.navigationTransition(.zoom(sourceID: sourceId, in: namespace))
            } else {
                content
            }
        } else {
            content
        }
    }
}
