// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData
import OSLog

// MARK: - Mode

enum AlbumDetailMode: Sendable {
    case full           // show all album songs (default — online catalog browsing)
    case downloadedOnly // show only downloaded tracks (Downloads/Offline contexts for purely-partial albums)
}

struct AlbumDetailView: View {
    private let albumId: String
    private let initialName: String
    private let coverArtId: String?
    private let initialDominantColor: Color
    private let initialCoverImage: PlatformImage?
    private let zoomSourceId: String?
    private let zoomNamespace: Namespace.ID?
    private let mode: AlbumDetailMode

    init(album: AlbumID3, zoomSourceId: String? = nil, zoomNamespace: Namespace.ID? = nil, coverArtId: String? = nil, initialDominantColor: Color = .clear, initialCoverImage: PlatformImage? = nil, mode: AlbumDetailMode = .full) {
        albumId = album.id
        initialName = album.name
        self.coverArtId = coverArtId
        self.initialDominantColor = initialDominantColor
        self.initialCoverImage = initialCoverImage
        let cid = "album:\(album.id)"
        let aid = album.id
        _albumFavoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
        _downloadedAlbumTracks = Query(filter: #Predicate<DownloadedTrack> { $0.albumId == aid })
        self.zoomSourceId = zoomSourceId
        self.zoomNamespace = zoomNamespace
        self.mode = mode
        _dominantColor = State(initialValue: initialDominantColor)
    }

    init(albumId: String, albumName: String, zoomSourceId: String? = nil, zoomNamespace: Namespace.ID? = nil, coverArtId: String? = nil, initialDominantColor: Color = .clear, initialCoverImage: PlatformImage? = nil, mode: AlbumDetailMode = .full) {
        self.albumId = albumId
        self.initialName = albumName
        self.coverArtId = coverArtId
        self.initialDominantColor = initialDominantColor
        self.initialCoverImage = initialCoverImage
        let cid = "album:\(albumId)"
        let aid = albumId
        _albumFavoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
        _downloadedAlbumTracks = Query(filter: #Predicate<DownloadedTrack> { $0.albumId == aid })
        self.zoomSourceId = zoomSourceId
        self.zoomNamespace = zoomNamespace
        self.mode = mode
        _dominantColor = State(initialValue: initialDominantColor)
    }

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: AlbumDetailViewModel?
    @State private var dominantColor: Color = .clear
    @State private var heroHeight: CGFloat = 680
    @State private var showDeleteAlert = false
    @State private var songToAddToPlaylist: DisplayableSong?
    @Query private var albumFavoriteMatches: [FavoriteRecord]
    @Query private var downloadedAlbumTracks: [DownloadedTrack]

    private var isAlbumFavorite: Bool { !albumFavoriteMatches.isEmpty }
    private var downloadedCount: Int { downloadedAlbumTracks.count }
    private var isOnline: Bool { container?.serverState.isOnline == true }
    /// Cover id the album theme is keyed on — the colour override is stored under the same id so it takes effect.
    private var albumCoverId: String { viewModel?.coverArtId ?? coverArtId ?? albumId }
    /// Every cover id the override must cover so it's resolved from ANY surface: the album cover + each song's
    /// own cover id (these can differ from the album's while pointing at the same artwork — e.g. the full player).
    private var albumThemeIds: [String] {
        [albumCoverId] + (viewModel?.songs.compactMap { $0.coverArtId } ?? [])
    }
    private var isLoadingSkeleton: Bool {
        viewModel == nil || (viewModel?.isLoading == true && viewModel?.songs.isEmpty == true)
    }
    private var headerTextColor: Color { theme.contentColor }
    private var headerSecondaryColor: Color { theme.secondaryContentColor }
    private var heroIconColor: Color {
        colorScheme == .dark ? Color.cassetteAccentSecondary : CassetteColors.accentForeground(on: dominantColor)
    }
    /// Unified (background, glyph/label) for every hero over-cover button — decided from the COVER's
    /// dominantColor (dark cover -> white + dominant glyph; else -> dark-violet + white glyph).
    private var heroButtonVariant: (background: Color, foreground: Color) {
        CassetteColors.heroButtonVariant(on: dominantColor)
    }
    private var theme: PlaylistTheme { PlaylistTheme(dominantColor: dominantColor) }
    private var bodyColor: Color { theme.isThemed ? theme.dominantColor : systemBackgroundColor }
    private var systemBackgroundColor: Color {
        #if canImport(UIKit)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    private var effectiveInitialImage: PlatformImage? {
        initialCoverImage ?? artworkImageCache.cachedImage(for: coverArtId ?? albumId)
    }

    // MARK: - Song filtering

    private var offlineFallbackSongs: [DisplayableSong] {
        downloadedAlbumTracks
            .sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
            .map { DisplayableSong(from: $0) }
    }

    private func filteredSongs(_ vmSongs: [DisplayableSong]) -> [DisplayableSong] {
        switch mode {
        case .full:
            return vmSongs
        case .downloadedOnly:
            let downloadedIds = Set(downloadedAlbumTracks.map(\.songId))
            return vmSongs.filter { downloadedIds.contains($0.id) }
        }
    }

    private func displaySongs() -> [DisplayableSong] {
        switch mode {
        case .downloadedOnly:
            if let vm = viewModel, vm.error == nil, !vm.songs.isEmpty {
                return filteredSongs(vm.songs)
            }
            return offlineFallbackSongs
        case .full:
            // Prefer the VM's catalog list, but back-stop with downloaded tracks whenever
            // the VM produced nothing — whether it errored OR returned an empty-success
            // payload (captive proxy / Cloudflare-WARP). This is the view-level safety net
            // that keeps a downloaded album readable through normal nav, not just Downloads.
            if let vm = viewModel, !vm.songs.isEmpty {
                return vm.songs
            }
            return offlineFallbackSongs
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let songs = displaySongs()
                albumHeader(vm: viewModel, songs: songs)
                    .frame(maxWidth: .infinity)

                if isLoadingSkeleton {
                    skeletonRows
                } else if let vm = viewModel {
                    let serverId = container?.serverState.activeServer?.id ?? UUID()
                    if songs.isEmpty {
                        if mode == .downloadedOnly {
                            EmptyStateView(
                                systemImage: "arrow.down.circle.slash",
                                title: "No Downloaded Tracks",
                                subtitle: "No tracks from this album have been downloaded."
                            )
                        } else if let error = vm.error {
                            EmptyStateView(
                                systemImage: "exclamationmark.triangle",
                                title: "Unable to Load Album",
                                subtitle: error.displayMessage,
                                action: .init(label: "Retry") { Task { await vm.load() } }
                            )
                        } else {
                            EmptyStateView(
                                systemImage: "music.note",
                                title: "No Tracks",
                                subtitle: "This album doesn't have any tracks yet."
                            )
                        }
                    } else {
                        AlbumSongRows(
                            songs: songs,
                            albumId: albumId,
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
                            onDownload: (mode == .downloadedOnly || vm.isOffline || vm.isDownloadingAlbum) ? nil : { songId in
                                Task { await vm.downloadSong(id: songId) }
                            },
                            onRemoveDownload: { songId in
                                Task { try? await container?.downloadService.remove(songId: songId, serverId: serverId) }
                            },
                            onAddToPlaylist: { song in songToAddToPlaylist = song }
                        )
                    }
                }
            }
        }
        .refreshable { await viewModel?.load() }
        .miniPlayerBottomMargin()
        // Extend the scroll content under the transparent nav bar so the cover reaches the screen top.
        .ignoresSafeArea(.container, edges: .top)
        // No soft blur under the nav bar (the cover scrolls under it; the system effect would flicker).
        .cassetteHideTopScrollEdgeEffect()
        .alert("Remove downloaded album?", isPresented: $showDeleteAlert) {
            Button("Remove", role: .destructive) { Task { await viewModel?.deleteDownload() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The audio files will be deleted from this device.")
        }
        .sheet(item: $songToAddToPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
        // Solid page color the cover melts into; the cover scrolls in the header (ImmersiveCoverHero).
        .background(bodyColor.ignoresSafeArea())
        .background {
            GeometryReader { proxy in
                Color.clear
                    // Square hero = the cover's own ratio, so the (square) artwork fits ENTIRELY without
                    // overflowing/cropping. The immersive melt + floating content stay.
                    .onAppear { heroHeight = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, w in heroHeight = w }
            }
        }
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(headerTextColor)
                        .cassetteHeroButton(size: 34)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .primaryAction) {
                // Manual theme-colour override (defaults to the cover's dominant). Persisted per cover; applied
                // live to the album theme and app-wide (e.g. the full player) via DominantColorExtractor.
                ColorPicker("", selection: Binding(
                    get: { colorExtractor.cachedColor(for: albumCoverId) ?? dominantColor },
                    set: { newColor in
                        colorExtractor.setColorOverride(newColor, forIds: albumThemeIds)
                        dominantColor = newColor
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("Theme colour")
                .contextMenu {
                    if colorExtractor.colorOverride(for: albumCoverId) != nil {
                        Button("Reset to cover colour", systemImage: "arrow.uturn.backward") {
                            colorExtractor.setColorOverride(nil, forIds: albumThemeIds)
                            let extracted = colorExtractor.cachedColor(for: albumCoverId) ?? dominantColor
                            dominantColor = extracted
                        }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
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
                        .foregroundStyle(headerTextColor)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAlbumFavorite)
                        .cassetteHeroButton(size: 34)
                }
                .buttonStyle(.plain)
                .disabled(!isOnline)
            }
        }
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(theme.isThemed ? (theme.isLight ? .light : .dark) : nil, for: .navigationBar)
        #endif
        // Keyed on connectivity so the list re-loads from the right source when
        // NWPathMonitor flips isOnline — same pattern as AlbumDetailMacOS and
        // PlaylistDetailView.
        .task(id: container?.serverState.isOnline) {
            guard let c = container else { return }
            if viewModel == nil {
                viewModel = AlbumDetailViewModel(
                    albumId: albumId,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
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
                return
            }

            await loadDominantColor(coverArtId: artId)
        }
        .cassetteZoomTransition(sourceID: zoomSourceId, in: zoomNamespace)
    }

    // MARK: - Skeleton rows

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
            .padding(.horizontal, CassetteSpacing.l)
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

    // MARK: - Download state

    private func downloadState(for vm: AlbumDetailViewModel) -> AlbumDownloadState {
        let total = vm.songs.count
        guard total > 0 else { return .notDownloaded }
        let downloaded = vm.songs.filter { $0.isDownloaded }.count
        if downloaded == 0 { return .notDownloaded }
        if downloaded == total { return .fullyDownloaded }
        return .partiallyDownloaded
    }

    // MARK: - Header

    private func albumHeader(vm: AlbumDetailViewModel?, songs: [DisplayableSong]) -> some View {
        return ImmersiveCoverHero(
            coverArtId: vm?.coverArtId ?? coverArtId ?? albumId,
            coverImage: effectiveInitialImage,
            theme: theme,
            heroHeight: heroHeight,
            contentBelow: true
        ) {
            VStack(spacing: CassetteSpacing.l) {
                VStack(spacing: 0) {
                    Text(vm?.albumName ?? initialName)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(headerTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, CassetteSpacing.xs)
                if vm == nil {
                    SkeletonBlock(width: 140, height: 18, cornerRadius: 4)
                        .padding(.bottom, CassetteSpacing.s)
                } else if let artist = vm?.artistName {
                    if let artistId = vm?.artistId, vm?.isOffline != true {
                        NavigationLink(value: HomeDestination.artist(ArtistID3(id: artistId, name: artist))) {
                            Text(artist)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(headerSecondaryColor)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, CassetteSpacing.s)
                    } else {
                        Text(artist)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(headerSecondaryColor)
                            .padding(.bottom, CassetteSpacing.s)
                    }
                }
                if vm == nil {
                    SkeletonBlock(width: 100, height: 14, cornerRadius: 4)
                } else if let vm {
                    HStack(spacing: CassetteSpacing.s) {
                        if let year = vm.year { Text(String(year)) }
                        if let genre = vm.genre { Text("·"); Text(genre) }
                        if let format = songs.first?.audioFormat {
                            Text("·")
                            Image(systemName: "waveform")
                                .font(.system(size: 9, weight: .semibold))
                            Text(format.uppercased())
                        }
                    }
                    .font(.cassetteCaption)
                    .foregroundStyle(headerSecondaryColor.opacity(0.8))
                }
            }
            .padding(.horizontal, CassetteSpacing.l)

            HStack(spacing: CassetteSpacing.m) {
                Button {
                    HapticFeedback.medium.trigger()
                    Task {
                        guard !songs.isEmpty else { return }
                        try? await container?.playerService.play(tracks: songs.shuffled(), startIndex: 0)
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.cassetteCellTitle)
                        .foregroundStyle(headerTextColor)
                        .cassetteGlassButton(size: 44)
                }
                .disabled(songs.isEmpty)
                .opacity(vm == nil ? 0.4 : 1)

                PlayButton(action: {
                    Task {
                        guard !songs.isEmpty else { return }
                        try? await container?.playerService.play(tracks: songs, startIndex: 0)
                    }
                }, isDisabled: songs.isEmpty || (mode == .full && vm?.isDownloadingAlbum == true), accentColor: heroButtonVariant.background, labelColor: heroButtonVariant.foreground)
                .frame(maxWidth: 220)

                if mode == .downloadedOnly {
                    Button {
                        HapticFeedback.heavy.trigger()
                        let sid = container?.serverState.activeServer?.id ?? UUID()
                        let tracks = downloadedAlbumTracks
                        Task {
                            for track in tracks {
                                try? await container?.downloadService.remove(songId: track.songId, serverId: sid)
                            }
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.cassetteCellTitle)
                            .foregroundStyle(headerTextColor)
                            .cassetteGlassButton(size: 44)
                    }
                } else if vm?.isOffline != true {
                    if let vm {
                        if vm.isDownloadingAlbum {
                            Button { Task { await vm.cancelAlbumDownload() } } label: {
                                Image(systemName: "xmark")
                                    .font(.cassetteCellTitle)
                                    .foregroundStyle(headerTextColor)
                                    .cassetteGlassButton(size: 44)
                            }
                        } else {
                            switch downloadState(for: vm) {
                            case .notDownloaded:
                                Button { Task { await vm.downloadAlbum() } } label: {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.cassetteCellTitle)
                                        .foregroundStyle(headerTextColor)
                                        .cassetteGlassButton(size: 44)
                                }
                                .disabled(vm.songs.isEmpty)
                            case .partiallyDownloaded:
                                Button { Task { await vm.downloadMissingTracks() } } label: {
                                    Image(systemName: "arrow.down.circle.dotted")
                                        .font(.cassetteCellTitle)
                                        .foregroundStyle(headerTextColor)
                                        .cassetteGlassButton(size: 44)
                                }
                            case .fullyDownloaded:
                                Button {
                                    HapticFeedback.heavy.trigger()
                                    showDeleteAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.cassetteCellTitle)
                                        .foregroundStyle(headerTextColor)
                                        .cassetteGlassButton(size: 44)
                                }
                            }
                        }
                    } else {
                        Button { } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.cassetteCellTitle)
                                .foregroundStyle(headerTextColor)
                                .cassetteGlassButton(size: 44)
                        }
                        .disabled(true)
                        .opacity(0.4)
                    }
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, CassetteSpacing.l)

            if mode == .full, let vm, vm.isDownloadingAlbum {
                let total = vm.songs.count
                let downloaded = downloadedCount
                VStack(spacing: CassetteSpacing.xs) {
                    if downloaded == 0 {
                        HStack(spacing: CassetteSpacing.s) {
                            ProgressView().scaleEffect(0.8)
                            Text("Starting download…")
                                .font(.cassetteCaption)
                                .foregroundStyle(headerSecondaryColor)
                        }
                    } else {
                        ProgressView(value: Double(downloaded), total: Double(max(total, 1)))
                            .progressViewStyle(.linear)
                            .tint(CassetteColors.accentForeground(on: dominantColor))
                            .frame(maxWidth: 280)
                        Text("Downloading \(downloaded)/\(total) tracks")
                            .font(.cassetteCaption)
                            .foregroundStyle(headerSecondaryColor)
                    }
                }
                .frame(minHeight: 44)
            }
            }
        }
    }
}

// MARK: - Download state

private nonisolated enum AlbumDownloadState {
    case notDownloaded
    case partiallyDownloaded
    case fullyDownloaded
}

// MARK: - Live download indicator rows

/// Sub-view that observes DownloadedTrack changes live via @Query,
/// overriding the isDownloaded flag per row without requiring a VM reload.
struct AlbumSongRows: View {
    let songs: [DisplayableSong]
    let downloadingIds: Set<String>
    let titleColor: Color
    let secondaryColor: Color
    let onTap: (Int) -> Void
    let onDownload: ((String) -> Void)?
    let onRemoveDownload: ((String) -> Void)?
    let onAddToPlaylist: ((DisplayableSong) -> Void)?

    @Query private var downloadedTracks: [DownloadedTrack]
    @Query private var allFavorites: [FavoriteRecord]

    private var favoriteSongIds: Set<String> {
        Set(allFavorites.map(\.id))
    }

    init(songs: [DisplayableSong], albumId: String, serverId: UUID, downloadingIds: Set<String> = [], titleColor: Color = .primary, secondaryColor: Color = .secondary, onTap: @escaping (Int) -> Void, onDownload: ((String) -> Void)? = nil, onRemoveDownload: ((String) -> Void)? = nil, onAddToPlaylist: ((DisplayableSong) -> Void)? = nil) {
        self.songs = songs
        self.downloadingIds = downloadingIds
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.onTap = onTap
        self.onDownload = onDownload
        self.onRemoveDownload = onRemoveDownload
        self.onAddToPlaylist = onAddToPlaylist
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
            let liveSong = song.withDownloaded(liveDownloaded)
            let isDownloading = downloadingIds.contains(song.id)
            let downloadAction: (() -> Void)? = (liveDownloaded || isDownloading) ? nil : onDownload.map { action in { action(song.id) } }
            let removeAction: (() -> Void)? = liveDownloaded ? onRemoveDownload.map { action in { action(song.id) } } : nil
            #if os(macOS)
            SongRow(song: liveSong, index: index + 1, isFavorite: favoriteSongIds.contains("song:\(song.id)"), titleColor: titleColor, secondaryColor: secondaryColor, onDownload: downloadAction, onRemoveDownload: removeAction, isDownloading: isDownloading, onAddToPlaylist: onAddToPlaylist)
                .padding(.horizontal, CassetteSpacing.l)
                .onTapGesture { onTap(index) }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            #else
            VStack(spacing: 0) {
                SongRow(song: liveSong, index: index + 1, isFavorite: favoriteSongIds.contains("song:\(song.id)"), titleColor: titleColor, secondaryColor: secondaryColor, onDownload: downloadAction, onRemoveDownload: removeAction, isDownloading: isDownloading, onAddToPlaylist: onAddToPlaylist)
                    .padding(.horizontal, CassetteSpacing.l)
                    .onTapGesture { onTap(index) }
                if index < songs.count - 1 {
                    Divider()
                        .padding(.leading, CassetteSpacing.l)
                }
            }
            #endif
        }
    }
}

