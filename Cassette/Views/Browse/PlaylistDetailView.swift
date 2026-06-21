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

    // Immersive hero geometry (captured from the view; tunable). `heroHeight` = the cover region height; the
    // cover lives in the first SCROLLING row and bleeds under the nav bar via ignoresSafeArea.
    @State private var heroHeight: CGFloat = 680

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

    /// Solid body color the cover melts into (the themed dominant color, or the system background until it
    /// resolves). Used by the immersive background and by the track-list row backgrounds, so the rows
    /// occlude the fixed full-bleed cover as they scroll up over it.
    private var bodyColor: Color {
        if theme.isThemed { return theme.dominantColor }
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }

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
                    .listRowBackground(bodyColor)
                } else if songs.isEmpty {
                    EmptyStateView(
                        systemImage: "music.note.list",
                        title: "Empty Playlist",
                        subtitle: "This playlist doesn't have any tracks yet."
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(bodyColor)
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
                        onAddToPlaylist: { song in songToAddToPlaylist = song },
                        // Solid backing per row so the rows occlude the fixed full-bleed cover on scroll.
                        rowBackground: bodyColor
                    )

                    let featured = FeaturedArtist.from(songs)
                    if !featured.isEmpty {
                        featuredArtistsSection(featured)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(bodyColor)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Extend the scroll content under the transparent nav bar so the first row's cover reaches the
        // screen top (and scrolls up under the bar). The bottom safe area / mini-player margin is preserved.
        .ignoresSafeArea(.container, edges: .top)
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
        // Solid page color the track list always sits on. The cover itself now lives in the (scrolling)
        // header row, so it scrolls up with the content instead of staying fixed behind it.
        .background(bodyColor.ignoresSafeArea())
        // Capture the hero region height (the cover lives in the first scrolling row, sized to this).
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { heroHeight = max(proxy.size.height * 0.9, proxy.size.width) }
                    .onChange(of: proxy.size.height) { _, h in heroHeight = max(h * 0.9, proxy.size.width) }
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
        .toolbar { toolbarContent }
        // Transparent nav bar so the cover floats under it; adapt the status-bar style to the cover
        // lightness (dark text on a light cover, light text on a dark cover).
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(theme.isThemed ? (theme.isLight ? .light : .dark) : nil, for: .navigationBar)
        #endif
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
                navBarIcon("chevron.left")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showEditSheet = true
            } label: {
                navBarIcon("pencil")
            }
            .disabled(container?.serverState.isOnline != true || viewModel?.playlistDetail == nil)
        }
    }

    /// A nav-bar icon using the app's shared over-cover treatment (the FullPlayer's glass button): the icon
    /// in the theme's adaptive content color over a Liquid-Glass / material circle tinted by the theme, so
    /// the chevron/pencil stay legible over any cover and on scroll — consistent with the transport buttons.
    private func navBarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.contentColor)
            .cassetteGlassButton(size: 34, tint: theme.glassTint)
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
            .listRowBackground(bodyColor)
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
        ZStack(alignment: .bottom) {
            // The cover + blurred melt live HERE, in the scroll content (the first row), so they scroll up
            // with the list. ignoresSafeArea(.container, .top) bleeds the cover under the transparent nav bar.
            GeometryReader { geo in
                // Stretchy header: on over-scroll at the top, grow the cover UPWARD to fill the bounce
                // instead of revealing the solid page color behind it.
                let stretch = max(0, geo.frame(in: .global).minY)
                PlaylistThemedBackground(
                    coverArtId: effectiveCoverArtId,
                    coverImage: initialCoverImage,
                    theme: theme,
                    heroHeight: heroHeight
                )
                .frame(width: geo.size.width, height: heroHeight + stretch)
                .offset(y: -stretch)
                .id(coverRefreshID)
            }
            .frame(height: heroHeight)

            VStack(spacing: CassetteSpacing.l) {
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
                    .frame(maxWidth: 220)

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
                .padding(.horizontal, CassetteSpacing.l)

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
            .padding(.bottom, CassetteSpacing.l)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
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
                                FeaturedArtistAvatar(artist: artist, size: 76)
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
    /// Solid backing applied to EACH row so the rows occlude a fixed full-bleed cover behind the List on
    /// scroll. `nil` = default List row background (the macOS detail has no fixed cover, so it passes nil).
    let rowBackground: Color?

    @Query private var downloadedTracks: [DownloadedTrack]
    @Query private var allFavorites: [FavoriteRecord]

    private var favoriteSongIds: Set<String> {
        Set(allFavorites.map(\.id))
    }

    init(songs: [DisplayableSong], serverId: UUID, downloadingIds: Set<String> = [], titleColor: Color = .primary, secondaryColor: Color = .secondary, onTap: @escaping (Int) -> Void, onDownload: ((String) -> Void)? = nil, onRemoveDownload: ((String) -> Void)? = nil, onRemove: ((Int) -> Void)? = nil, onReorder: ((IndexSet, Int) -> Void)? = nil, onContextRemove: ((Int) -> Void)? = nil, onAddToPlaylist: ((DisplayableSong) -> Void)? = nil, rowBackground: Color? = nil) {
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
        self.rowBackground = rowBackground
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
                    .listRowBackground(rowBackground)
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
                    .listRowBackground(rowBackground)
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
