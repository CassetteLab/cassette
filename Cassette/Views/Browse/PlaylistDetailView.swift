// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData
import OSLog

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
        let pid = playlist.id
        _downloadedPlaylistMatches = Query(filter: #Predicate<DownloadedPlaylist> { $0.playlistId == pid })
        _dominantColor = State(initialValue: initialDominantColor)
    }

    init(playlist: DownloadedPlaylist, coverArtId: String? = nil, initialDominantColor: Color = .clear, initialCoverImage: PlatformImage? = nil, zoomSourceId: String? = nil, zoomNamespace: Namespace.ID? = nil) {
        playlistId = playlist.playlistId
        initialName = playlist.name
        self.coverArtId = coverArtId
        self.initialDominantColor = initialDominantColor
        self.initialCoverImage = initialCoverImage
        self.zoomSourceId = zoomSourceId
        self.zoomNamespace = zoomNamespace
        let pid = playlist.playlistId
        _downloadedPlaylistMatches = Query(filter: #Predicate<DownloadedPlaylist> { $0.playlistId == pid })
        _dominantColor = State(initialValue: initialDominantColor)
    }

    init(playlistId: String, name: String, coverArtId: String? = nil, initialDominantColor: Color = .clear, initialCoverImage: PlatformImage? = nil, zoomSourceId: String? = nil, zoomNamespace: Namespace.ID? = nil) {
        self.playlistId = playlistId
        self.initialName = name
        self.coverArtId = coverArtId
        self.initialDominantColor = initialDominantColor
        self.initialCoverImage = initialCoverImage
        self.zoomSourceId = zoomSourceId
        self.zoomNamespace = zoomNamespace
        let pid = playlistId
        _downloadedPlaylistMatches = Query(filter: #Predicate<DownloadedPlaylist> { $0.playlistId == pid })
        _dominantColor = State(initialValue: initialDominantColor)
    }

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: PlaylistDetailViewModel?
    @State private var dominantColor: Color = .clear
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var songToAddToPlaylist: DisplayableSong?

    @State private var coverRefreshID = UUID()
    @AppStorage("coverArtUploadVersion") private var coverArtUploadVersion = 0

    // View-level offline backstop: sources the song list straight from SwiftData when the
    // view model produced nothing (empty-success or error). Mirrors AlbumDetailView's
    // downloaded fallback so a downloaded playlist stays readable independent of the
    // network, the VM, and connectivity detection. Keyed on playlistId here; serverId is
    // applied at read time since it isn't known at init.
    @Query private var downloadedPlaylistMatches: [DownloadedPlaylist]
    @Query private var allDownloadedTracks: [DownloadedTrack]


    /// The cover id actually displayed: the server cover, else the playlist id — under which a generated
    /// gradient cover is cached (`{playlistId}@{tier}`). Drives BOTH the cover and the theme derivation, so a
    /// gradient playlist (which has no server `coverArt`) is themed from its gradient, not left unthemed.
    private var effectiveCoverArtId: String { viewModel?.coverArtId ?? coverArtId ?? playlistId }

    /// The reusable theming engine, fed by this view's cover-derived `dominantColor` (the Phase-1 color
    /// source). Drives both the blended background and the adaptive foreground colors below.
    private var theme: PlaylistTheme { PlaylistTheme(dominantColor: dominantColor) }
    private var headerTextColor: Color { theme.contentColor }
    private var headerSecondaryColor: Color { theme.secondaryContentColor }

    /// Header metadata line, Apple-Music style: "N songs · Updated <relative date>".
    private func metadataLine(count: Int, updated: Date?) -> String {
        var parts = ["\(count) song\(count == 1 ? "" : "s")"]
        if let updated {
            parts.append("Updated \(updated.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
    private var heroIconColor: Color {
        colorScheme == .dark ? Color.cassetteAccentSecondary : CassetteColors.accentForeground(on: dominantColor)
    }
    private var isLoadingSkeleton: Bool {
        viewModel == nil || (viewModel?.isLoading == true && viewModel?.songs.isEmpty == true)
    }

    /// Downloaded tracks reconstructed from SwiftData in playlist order, independent of the
    /// view model. Used as the offline backstop when `viewModel.songs` is empty.
    private var downloadedFallbackSongs: [DisplayableSong] {
        guard let serverId = container?.serverState.activeServer?.id,
              let record = downloadedPlaylistMatches.first(where: { $0.serverId == serverId })
        else { return [] }
        let bySongId = Dictionary(
            allDownloadedTracks.filter { $0.serverId == serverId }.map { ($0.songId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return record.songIds.compactMap { bySongId[$0] }.map { DisplayableSong(from: $0) }
    }

    /// Prefer the view model's list; fall back to the downloaded copy when it is empty.
    private func resolvedSongs(_ vm: PlaylistDetailViewModel?) -> [DisplayableSong] {
        if let songs = vm?.songs, !songs.isEmpty { return songs }
        return downloadedFallbackSongs
    }

    var body: some View {
        // Kept as List to preserve PlaylistSongRows' .onDelete (swipe-to-remove).
        // ScrollView + LazyVStack refactor is deferred until that interaction is re-implemented outside List.
        List {
            playlistHeader(vm: viewModel)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if isLoadingSkeleton {
                skeletonRows
            } else if let vm = viewModel {
                let songs = resolvedSongs(vm)
                if songs.isEmpty, let error = vm.error {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Playlist",
                        subtitle: error.displayMessage,
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if songs.isEmpty {
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
                        songs: songs,
                        serverId: serverId,
                        downloadingIds: vm.downloadingIds,
                        titleColor: headerTextColor,
                        secondaryColor: headerSecondaryColor,
                        onTap: { index in
                            Task {
                                do {
                                    try await container?.playerService.play(tracks: songs, startIndex: index)
                                } catch {
                                    Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                                }
                            }
                        },
                        onDownload: (vm.isOffline || vm.isDownloadingPlaylist) ? nil : { songId in
                            Task { await vm.downloadSong(id: songId) }
                        },
                        onRemoveDownload: { songId in
                            Task { try? await container?.downloadService.remove(songId: songId, serverId: serverId) }
                        },
                        onRemove: !vm.isOffline ? { index in
                            Task { await vm.removeTrack(at: index) }
                        } : nil,
                        onContextRemove: !vm.isOffline ? { index in
                            Task { await vm.removeTrack(at: index) }
                        } : nil,
                        onAddToPlaylist: { song in songToAddToPlaylist = song }
                    )

                    let featured = FeaturedArtist.from(songs)
                    if !featured.isEmpty {
                        featuredArtistsSection(featured)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .miniPlayerBottomMargin()
        .refreshable { await viewModel?.load() }
        .alert("Remove downloaded playlist?", isPresented: $showDeleteAlert) {
            Button("Remove", role: .destructive) { Task { await viewModel?.deleteDownload() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The audio files will be deleted from this device.")
        }
        .sheet(item: $songToAddToPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
        .sheet(isPresented: $showEditSheet) {
            if let vm = viewModel, let c = container, let serverId = c.serverState.activeServer?.id {
                EditPlaylistSheet(
                    playlistId: playlistId,
                    serverId: serverId,
                    currentName: vm.name,
                    currentComment: vm.playlistDetail?.comment ?? "",
                    currentCoverArtId: effectiveCoverArtId,
                    songs: resolvedSongs(vm),
                    onCommitted: {
                        Task { await vm.load() }
                        coverRefreshID = UUID()
                        coverArtUploadVersion += 1
                    },
                    onDeleted: { dismiss() }
                )
                // Inject explicitly so the sheet never misses these (sheet env propagation has bitten us
                // before — see the toast overlay fix).
                .environment(colorExtractor)
                .environment(c.artworkImageCache)
                .environment(\.appContainer, c)
            }
        }
        .background(
            PlaylistThemedBackground(
                coverArtId: effectiveCoverArtId,
                coverImage: initialCoverImage,
                theme: theme
            )
        )
        .cassetteContentWidth()
        // Drive the now-playing indicator from the SAME color as the hero buttons (heroIconColor), not raw
        // accentForeground — heroIconColor adds the dark-mode branch (cassetteAccentSecondary), so the bars
        // now match the buttons on every background instead of diverging in dark mode.
        .environment(\.cassettePlayingAccent, heroIconColor)
        .navigationTitle("")
        .navigationBarTitleDisplayModeInline()
        .navigationBarBackButtonHidden(true)
        #if os(iOS)
        .enableSwipeBack()
        #endif
        .toolbar { toolbarContent }
        // Keyed on connectivity so the list re-loads from the right source when
        // NWPathMonitor flips isOnline — same pattern as PlaylistDetailMacOS.
        .task(id: container?.serverState.isOnline) {
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
        .task(id: effectiveCoverArtId) {
            let artId = effectiveCoverArtId
            let cached = colorExtractor.dominantColor(for: artId, image: nil)
            if cached != .clear {
                dominantColor = cached
                return
            }
            await loadDominantColor(coverArtId: artId)
        }
        .cassetteZoomTransition(sourceID: zoomSourceId, in: zoomNamespace)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showEditSheet = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(CassetteColors.accent)
            }
            .disabled(container?.serverState.isOnline != true || viewModel?.playlistDetail == nil)
        }
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
        guard let image = await container?.artworkImageCache.load(coverArtId: coverArtId) else { return }
        let color = colorExtractor.dominantColor(for: coverArtId, image: image)
        withAnimation(.easeIn(duration: 0.2)) {
            dominantColor = color
        }
    }

    // MARK: - Download state helpers

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
            // Cover art (editing the cover lives in the edit sheet now)
            coverArtContent(vm: vm)
                .padding(.top, CassetteSpacing.xxl)

            VStack(spacing: 0) {
                Text(vm?.name ?? initialName)
                    .font(.cassetteDetailTitle)
                    .foregroundStyle(headerTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, CassetteSpacing.xs)
                if vm == nil {
                    SkeletonBlock(width: 140, height: 18, cornerRadius: 4)
                        .padding(.bottom, CassetteSpacing.s)
                } else if let owner = vm?.owner {
                    Text("by \(owner)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(headerSecondaryColor)
                        .padding(.bottom, CassetteSpacing.s)
                }
                if vm == nil {
                    SkeletonBlock(width: 100, height: 14, cornerRadius: 4)
                } else if vm != nil {
                    let count = resolvedSongs(vm).count
                    Text(metadataLine(count: count, updated: vm?.playlistDetail?.changed))
                        .font(.cassetteCaption)
                        .foregroundStyle(headerSecondaryColor.opacity(0.8))
                }
            }
            .padding(.horizontal, CassetteSpacing.l)

            Group {
                HStack(spacing: CassetteSpacing.m) {
                    Button {
                        HapticFeedback.medium.trigger()
                        Task {
                            let shuffled = resolvedSongs(vm).shuffled()
                            guard !shuffled.isEmpty else { return }
                            try? await container?.playerService.play(tracks: shuffled, startIndex: 0)
                        }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.cassetteCellTitle)
                            .foregroundStyle(heroIconColor)
                            .cassetteGlassButton(size: 44)
                    }
                    .disabled(resolvedSongs(vm).isEmpty)
                    .opacity(vm == nil ? 0.4 : 1)

                    PlayButton(action: {
                        Task {
                            let songs = resolvedSongs(vm)
                            guard !songs.isEmpty else { return }
                            try? await container?.playerService.play(tracks: songs, startIndex: 0)
                        }
                    }, isDisabled: resolvedSongs(vm).isEmpty || (vm?.isDownloadingPlaylist == true), accentColor: heroIconColor)
                    .frame(maxWidth: 400)

                    if vm?.isOffline != true {
                        if let vm {
                            if vm.isDownloadingPlaylist {
                                Button { Task { await vm.cancelPlaylistDownload() } } label: {
                                    Image(systemName: "xmark")
                                        .font(.cassetteCellTitle)
                                        .foregroundStyle(heroIconColor)
                                        .cassetteGlassButton(size: 44)
                                }
                            } else {
                                switch downloadState(for: vm) {
                                case .notDownloaded:
                                    Button { Task { await vm.downloadPlaylist() } } label: {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.cassetteCellTitle)
                                            .foregroundStyle(heroIconColor)
                                            .cassetteGlassButton(size: 44)
                                    }
                                    .disabled(vm.songs.isEmpty)
                                case .partiallyDownloaded:
                                    Button { Task { await vm.downloadMissingTracks() } } label: {
                                        Image(systemName: "arrow.down.circle.dotted")
                                            .font(.cassetteCellTitle)
                                            .foregroundStyle(heroIconColor)
                                            .cassetteGlassButton(size: 44)
                                    }
                                case .fullyDownloaded:
                                    Button {
                                        HapticFeedback.heavy.trigger()
                                        showDeleteAlert = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.cassetteCellTitle)
                                            .foregroundStyle(heroIconColor)
                                            .cassetteGlassButton(size: 44)
                                    }
                                }
                            }
                        } else {
                            Button { } label: {
                                Image(systemName: "arrow.down.circle")
                                    .font(.cassetteCellTitle)
                                    .foregroundStyle(heroIconColor)
                                    .cassetteGlassButton(size: 44)
                            }
                            .disabled(true)
                            .opacity(0.4)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, CassetteSpacing.xxxl)

                if let vm, vm.isDownloadingPlaylist {
                    let serverId = container?.serverState.activeServer?.id ?? UUID()
                    PlaylistDownloadProgressView(
                        songs: vm.songs,
                        total: vm.songs.count,
                        serverId: serverId,
                        secondaryColor: headerSecondaryColor
                    )
                }
            }
        }
        .padding(.bottom, CassetteSpacing.xxl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func coverArtContent(vm: PlaylistDetailViewModel?) -> some View {
        // Skeleton only while genuinely still loading with no cover hint yet. Once the VM has loaded we
        // always render the card with the effective id (server cover, else playlistId) — a gradient
        // playlist has no server coverArt, so this is what surfaces its cached gradient in the hero
        // instead of a never-resolving skeleton.
        if (vm == nil || vm?.isLoading == true)
            && initialCoverImage == nil && coverArtId == nil && vm?.coverArtId == nil {
            SkeletonBlock(width: 220, height: 220, cornerRadius: CassetteCornerRadius.large)
        } else {
            CoverArtCard(
                id: vm?.coverArtId ?? coverArtId ?? playlistId,
                size: 300,
                cornerRadius: CassetteCornerRadius.large,
                initialImage: initialCoverImage
            )
            .id(coverRefreshID)
        }
    }

    /// Apple-Music "Featured Artists" rail: the most-present artists in the playlist as tappable circles
    /// → artist detail (reuses the existing `.cassetteNavigateToArtist` notification path). Only artists
    /// with an `artistId` appear (see FeaturedArtist); the circle uses a representative track cover.
    private func featuredArtistsSection(_ artists: [FeaturedArtist]) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Featured Artists")
                .font(.cassetteSectionTitle)
                .foregroundStyle(headerTextColor)
                .padding(.horizontal, CassetteSpacing.l)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: CassetteSpacing.m) {
                    ForEach(artists) { artist in
                        Button {
                            HapticFeedback.light.trigger()
                            postNavigateToArtist(artistId: artist.id, artistName: artist.name, coverArtId: artist.coverArtId)
                        } label: {
                            VStack(spacing: CassetteSpacing.xs) {
                                CoverArtView(id: artist.coverArtId ?? artist.id, size: 160, placeholderSystemImage: "music.mic")
                                    .frame(width: 76, height: 76)
                                    .clipShape(Circle())
                                Text(artist.name)
                                    .font(.cassetteCaption)
                                    .foregroundStyle(headerSecondaryColor)
                                    .lineLimit(1)
                                    .frame(width: 84)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CassetteSpacing.l)
                .padding(.bottom, CassetteSpacing.s)
            }
        }
        .padding(.top, CassetteSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Download state

private nonisolated enum PlaylistDownloadState {
    case notDownloaded
    case partiallyDownloaded(downloaded: Int, total: Int)
    case fullyDownloaded
}

// MARK: - Download progress sub-view

private struct PlaylistDownloadProgressView: View {
    let songs: [DisplayableSong]
    let total: Int
    let secondaryColor: Color

    @Query private var downloadedTracks: [DownloadedTrack]

    init(songs: [DisplayableSong], total: Int, serverId: UUID, secondaryColor: Color) {
        self.songs = songs
        self.total = total
        self.secondaryColor = secondaryColor
        let sid = serverId
        _downloadedTracks = Query(filter: #Predicate<DownloadedTrack> { $0.serverId == sid })
    }

    private var downloaded: Int {
        let downloadedIds = Set(downloadedTracks.map(\.songId))
        return songs.filter { downloadedIds.contains($0.id) }.count
    }

    var body: some View {
        VStack(spacing: CassetteSpacing.xs) {
            if downloaded == 0 {
                HStack(spacing: CassetteSpacing.s) {
                    ProgressView().scaleEffect(0.8)
                    Text("Starting download…")
                        .font(.cassetteCaption)
                        .foregroundStyle(secondaryColor)
                }
            } else {
                ProgressView(value: Double(downloaded), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(Color.cassetteAccent)
                    .frame(maxWidth: 280)
                Text("Downloading \(downloaded)/\(total) tracks")
                    .font(.cassetteCaption)
                    .foregroundStyle(secondaryColor)
            }
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Camera picker (iOS only)

#if os(iOS)
private struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

// MARK: - Live download indicator rows

/// Sub-view that observes DownloadedTrack changes live via @Query,
/// overriding the isDownloaded flag per row without requiring a VM reload.
struct PlaylistSongRows: View {
    let songs: [DisplayableSong]
    let downloadingIds: Set<String>
    let titleColor: Color
    let secondaryColor: Color
    let onTap: (Int) -> Void
    let onDownload: ((String) -> Void)?
    let onRemoveDownload: ((String) -> Void)?
    let onRemove: ((Int) -> Void)?
    let onReorder: ((IndexSet, Int) -> Void)?
    let onContextRemove: ((Int) -> Void)?
    let onAddToPlaylist: ((DisplayableSong) -> Void)?

    @Query private var downloadedTracks: [DownloadedTrack]
    @Query private var allFavorites: [FavoriteRecord]

    private var favoriteSongIds: Set<String> {
        Set(allFavorites.map(\.id))
    }

    init(songs: [DisplayableSong], serverId: UUID, downloadingIds: Set<String> = [], titleColor: Color = .primary, secondaryColor: Color = .secondary, onTap: @escaping (Int) -> Void, onDownload: ((String) -> Void)? = nil, onRemoveDownload: ((String) -> Void)? = nil, onRemove: ((Int) -> Void)? = nil, onReorder: ((IndexSet, Int) -> Void)? = nil, onContextRemove: ((Int) -> Void)? = nil, onAddToPlaylist: ((DisplayableSong) -> Void)? = nil) {
        self.songs = songs
        self.downloadingIds = downloadingIds
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.onTap = onTap
        self.onDownload = onDownload
        self.onRemoveDownload = onRemoveDownload
        self.onRemove = onRemove
        self.onReorder = onReorder
        self.onContextRemove = onContextRemove
        self.onAddToPlaylist = onAddToPlaylist
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
            albumId: song.albumId,
            albumName: song.albumName,
            artistId: song.artistId,
            genre: song.genre,
            duration: song.duration,
            trackNumber: song.trackNumber,
            isDownloaded: liveDownloaded,
            coverArtId: song.coverArtId,
            audioFormat: song.audioFormat,
            replayGainTrackGain: song.replayGainTrackGain,
            replayGainTrackPeak: song.replayGainTrackPeak,
            replayGainAlbumGain: song.replayGainAlbumGain,
            replayGainAlbumPeak: song.replayGainAlbumPeak,
            replayGainBaseGain: song.replayGainBaseGain,
            replayGainFallbackGain: song.replayGainFallbackGain
        )
        let isDownloading = downloadingIds.contains(song.id)
        let downloadAction: (() -> Void)? = (liveDownloaded || isDownloading) ? nil : onDownload.map { action in { action(song.id) } }
        let removeAction: (() -> Void)? = liveDownloaded ? onRemoveDownload.map { action in { action(song.id) } } : nil
        SongRow(song: liveSong, index: index + 1, showCoverArt: true, isFavorite: favoriteSongIds.contains("song:\(song.id)"), titleColor: titleColor, secondaryColor: secondaryColor, onDownload: downloadAction, onRemoveDownload: removeAction, isDownloading: isDownloading, onRemoveFromPlaylist: onContextRemove.map { remove in { remove(index) } }, onAddToPlaylist: onAddToPlaylist)
            .contentShape(Rectangle())
            .onTapGesture { onTap(index) }
            .listRowBackground(Color.clear)
        #if os(macOS)
        .listRowSeparator(.hidden)
        #endif
    }
}
