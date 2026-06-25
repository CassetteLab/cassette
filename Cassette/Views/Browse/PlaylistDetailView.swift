// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData
import OSLog
#if os(iOS)
import UniformTypeIdentifiers
#endif

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
    /// A user-picked gradient spec (if any) -> the hero renders CRISP from it instead of the JPEG. Resolved
    /// from PlaylistCoverStore on appear + after an edit (coverRefreshID). Nil for photo / server cover.
    @State private var gradientSpec: PlaylistGradientSpec?
    @State private var showDeleteAlert = false
    @State private var showAddMusic = false
    @State private var songToAddToPlaylist: DisplayableSong?

    @State private var coverRefreshID = UUID()

    // MARK: In-place edit mode (iOS only — macOS keeps EditPlaylistSheet). The detail view becomes the editor:
    // hero → editable cover carousel, title/description → fields, track list (Gate 2) → reorder + multi-select.
    // Reuses the validated PlaylistCoverCarousel + the mutation committer — only the CONTAINER changes.
    @State private var isEditing = false
    @State private var editName: String = ""
    @State private var editComment: String = ""
    /// Local mutable working copy of the track list — reorder (drag) + multi-select remove both mutate this;
    /// the commit does ONE atomic full-list replace (Gate 3) if it differs from the loaded songs.
    @State private var editSongs: [DisplayableSong] = []
    @State private var selectedSongIds: Set<String> = []
    @State private var selectedGradient: PlaylistGradientShape?
    @State private var photoIsCover = false
    @State private var coverDirty = false
    @State private var showDeletePlaylistConfirm = false
    @State private var showRemoveSongsConfirm = false
    @State private var isSaving = false
    #if os(iOS)
    @State private var pendingImage: UIImage?
    @State private var showImageOptions = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var imageToCrop: CroppableImage?
    #endif

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
    /// Unified (background, glyph/label) for every hero over-cover button — decided from the COVER's
    /// dominantColor (dark cover -> white + dominant glyph; else -> dark-violet + white glyph).
    private var heroButtonVariant: (background: Color, foreground: Color) {
        CassetteColors.heroButtonVariant(on: dominantColor)
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
        List(selection: $selectedSongIds) {
            Group {
                if isEditing {
                    editHeader
                        .transition(.opacity)
                } else {
                    playlistHeader(vm: viewModel)
                        .transition(.opacity)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if isLoadingSkeleton {
                skeletonRows
            } else if isEditing {
                editableSongRows
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
                    // One closure shared by the swipe-delete (onRemove) and the context menu (onContextRemove) so
                    // the two paths can't drift; nil offline (no edits).
                    let removeTrack: ((Int) -> Void)? = vm.isOffline ? nil : { index in
                        Task { await vm.removeTrack(at: index) }
                    }
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
                        onRemove: removeTrack,
                        onContextRemove: removeTrack,
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
        #if os(iOS)
        // Edit mode ONLY while editing — nil otherwise. Forcing an editMode binding (even .inactive) in view
        // mode broke the List's scrolling; nil restores the default (normal scroll) for the read-only view.
        .environment(\.editMode, isEditing ? Binding.constant(EditMode.active) : nil)
        #endif
        .scrollContentBackground(.hidden)
        // Extend the scroll content under the transparent nav bar so the first row's cover reaches the
        // screen top (and scrolls up under the bar). The bottom safe area / mini-player margin is preserved.
        .ignoresSafeArea(.container, edges: .top)
        // No soft blur under the nav bar (the cover scrolls under it; the system effect would flicker).
        .cassetteHideTopScrollEdgeEffect()
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
        #if os(iOS)
        // In-place edit cover photo flow (mirrors the create/edit sheets: pick → Apple-Photos crop).
        .confirmationDialog("Cover Art", isPresented: $showImageOptions, titleVisibility: .visible) {
            Button("Choose from Library") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showImagePicker = true }
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take a Photo") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCamera = true }
                }
            }
            Button("Browse Files") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showFilePicker = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showImagePicker) {
            ImagePickerController(sourceType: .photoLibrary, allowsEditing: false, onPick: { presentCrop($0) }, onCancel: {})
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePickerController(sourceType: .camera, allowsEditing: false, onPick: { presentCrop($0) }, onCancel: {})
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $imageToCrop) { croppable in
            SquareCropView(image: croppable.image, onCrop: { pendingImage = $0; imageToCrop = nil }, onCancel: { imageToCrop = nil })
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.jpeg, .png, .heic, .webP], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { presentCrop(img) }
        }
        #endif
        .deletePlaylistConfirmation(
            playlistName: viewModel?.name ?? initialName,
            isPresented: $showDeletePlaylistConfirm,
            hasDownloads: (viewModel?.songs.contains { $0.isDownloaded } ?? false) || !downloadedPlaylistMatches.isEmpty
        ) { purgeDownloads in
            Task { await deletePlaylistInPlace(purgeDownloads: purgeDownloads) }
        }
        .alert("Remove \(selectedSongIds.count) Song\(selectedSongIds.count == 1 ? "" : "s")?", isPresented: $showRemoveSongsConfirm) {
            Button("Remove", role: .destructive) { removeSelectedTracks() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll be removed from the playlist when you save.")
        }
        .sheet(isPresented: $showAddMusic) {
            if let vm = viewModel, let c = container, let serverId = c.serverState.activeServer?.id {
                AddMusicSheet(
                    playlistName: vm.name,
                    existingTrackIds: resolvedSongs(vm).map(\.id)
                ) { added in
                    await AddMusicCommitter.commit(
                        addedSongs: added,
                        playlistId: playlistId,
                        serverId: serverId,
                        existingTrackIds: resolvedSongs(vm).map(\.id),
                        currentComment: vm.playlistDetail?.comment ?? "",
                        container: c,
                        colorExtractor: colorExtractor
                    )
                    await vm.load()
                    coverRefreshID = UUID()
                }
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
            // Photo / server cover -> extract the dominant. Gradient playlists are themed from the spec base
            // color (cover-refresh task), not the JPEG, so gradient + body stay coherent.
            guard gradientSpec == nil else { return }
            let artId = effectiveCoverArtId
            let cached = colorExtractor.dominantColor(for: artId, image: nil)
            if cached != .clear {
                dominantColor = cached
                return
            }
            await loadDominantColor(coverArtId: artId)
        }
        .task(id: coverRefreshID) {
            // A user-picked gradient -> render the hero CRISP from the spec (the JPEG stays the
            // cards/cross-device truth), AND theme the body straight from the (vibrance-boosted) spec base
            // color so gradient + background + body stay coherent, no JPEG re-extraction. Re-resolves after an
            // edit (coverRefreshID bumps). Nil -> JPEG/photo path keeps the extractor.
            guard let container, let serverId = container.serverState.activeServer?.id else { gradientSpec = nil; return }
            let choice = PlaylistCoverStore(modelContainer: container.modelContainer).choice(playlistId: playlistId, serverId: serverId)
            let spec = choice?.isUserPicked == true ? choice?.spec : nil
            gradientSpec = spec
            if let spec {
                withAnimation(.easeIn(duration: 0.2)) { dominantColor = spec.baseColor }
            }
        }
        .cassetteZoomTransition(sourceID: zoomSourceId, in: zoomNamespace)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            // Same themed hero-button surface as view mode (navBarIcon: opaque circle + headerTextColor) so the
            // edit CTAs match the non-edit ones — NOT system glass capsules, which read the wrong colour here.
            ToolbarItem(placement: .cancellationAction) {
                Button { cancelEdit() } label: { navBarIcon("xmark") }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .primaryAction) {
                // Trash: multi-remove the selected tracks; with nothing selected, delete the whole playlist
                // (confirmed via dialog). Both mutate only the local working list until Done persists.
                Button(role: .destructive) {
                    if selectedSongIds.isEmpty { showDeletePlaylistConfirm = true } else { showRemoveSongsConfirm = true }
                } label: {
                    navBarIcon("trash", tint: .red)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showAddMusic = true } label: { navBarIcon("plus") }
                    .buttonStyle(.plain)
                    .disabled(isSaving || container?.serverState.isOnline != true)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView().controlSize(.small).tint(headerTextColor)
                } else {
                    let canSave = !editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button { Task { isSaving = true; await commitEdit(); isSaving = false } } label: { navBarIcon("checkmark") }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                }
            }
        } else {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    navBarIcon("chevron.left")
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddMusic = true
                } label: {
                    navBarIcon("plus")
                }
                .buttonStyle(.plain)
                .disabled(container?.serverState.isOnline != true || viewModel?.playlistDetail == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    enterEdit()
                } label: {
                    navBarIcon("pencil")
                }
                .buttonStyle(.plain)
                .disabled(container?.serverState.isOnline != true || viewModel?.playlistDetail == nil)
            }
        }
    }

    /// A nav-bar icon on the unified hero button surface (opaque solid circle, same variant as the transport
    /// + Play). The opaque circle + `.buttonStyle(.plain)` on the ToolbarItem button replace the native
    /// toolbar Liquid-Glass, so there is a SINGLE background, not two stacked layers.
    private func navBarIcon(_ systemName: String, tint: Color? = nil) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint ?? headerTextColor)
            .cassetteHeroButton(size: 34)
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

    // MARK: - In-place edit header (iOS in-place editor; reuses the validated carousel + fields)

    private var editHeader: some View {
        VStack(spacing: CassetteSpacing.xl) {
            editCoverCarousel
                // Clear the (edit-mode) nav bar since the list bleeds under it via ignoresSafeArea(.top).
                .padding(.top, 100)
            VStack(spacing: CassetteSpacing.s) {
                TextField("Playlist Title", text: $editName)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, CassetteSpacing.s)
                TextField("Description", text: $editComment, axis: .vertical)
                    .multilineTextAlignment(.center)
                    .lineLimit(1...4)
            }
            .padding(.horizontal, CassetteSpacing.l)
        }
        .padding(.bottom, CassetteSpacing.l)
    }

    private var editCoverCarousel: some View {
        PlaylistCoverCarousel(
            title: editName,
            selectedGradient: selectedGradient,
            isPhotoSelected: photoIsCover,
            photoPreview: editPhotoPreview,
            showsPhotoOption: editShowsPhotoOption,
            leadingLabel: "Current",
            leadingCoverArtId: effectiveCoverArtId,
            onSelectLeading: {
                selectedGradient = nil
                photoIsCover = false
                coverDirty = true
            },
            onSelectPhoto: {
                selectedGradient = nil
                photoIsCover = true
                coverDirty = true
            },
            onRequestPhotoPicker: {
                selectedGradient = nil
                photoIsCover = true
                coverDirty = true
                #if os(iOS)
                showImageOptions = true
                #endif
            },
            onSelectGradient: { shape in
                selectedGradient = shape
                photoIsCover = false
                coverDirty = true
            }
        )
    }

    private var editShowsPhotoOption: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    private var editPhotoPreview: PlatformImage? {
        #if os(iOS)
        return pendingImage
        #else
        return nil
        #endif
    }

    /// Enter in-place edit: snapshot the current metadata + cover choice into the working edit state, animate in.
    private func enterEdit() {
        editName = viewModel?.name ?? initialName
        editComment = viewModel?.playlistDetail?.comment ?? ""
        editSongs = resolvedSongs(viewModel)
        selectedSongIds = []
        selectedGradient = nil
        photoIsCover = false
        coverDirty = false
        #if os(iOS)
        pendingImage = nil
        #endif
        loadEditGradientChoice()
        withAnimation(.smooth) { isEditing = true }
    }

    /// Cancel in-place edit: discard the working state without mutating anything.
    private func cancelEdit() {
        withAnimation(.smooth) { isEditing = false }
    }

    /// Commit in-place edit: the SAME mutation sequence as EditPlaylistSheet.commit() — rename, the atomic
    /// full-list replace (reorder + multi-remove), the R1 comment re-assert, the cover apply, and the
    /// first-track color derivation — then refresh the detail view and animate back to view mode.
    private func commitEdit() async {
        guard let c = container, let serverId = c.serverState.activeServer?.id else {
            withAnimation(.smooth) { isEditing = false }
            return
        }
        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComment = editComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentName = viewModel?.name ?? initialName
        let currentComment = viewModel?.playlistDetail?.comment ?? ""
        let commentChanged = trimmedComment != currentComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalSongs = resolvedSongs(viewModel)
        let songsChanged = editSongs.map(\.id) != originalSongs.map(\.id)

        if !trimmedName.isEmpty && trimmedName != currentName.trimmingCharacters(in: .whitespacesAndNewlines) {
            try? await c.playlistService.renamePlaylist(id: playlistId, newName: trimmedName)
        }
        // Atomic full-list replace — the single track-mutation path (reorder + multi-select remove).
        if songsChanged {
            try? await c.playlistService.reorderTracks(playlistId: playlistId, orderedSongIds: editSongs.map(\.id))
        }
        // R1 guard: re-assert a non-empty comment after the replace (it doesn't survive createPlaylist); always
        // write a changed comment. One write covers the guard + a description edit. NO name re-assert.
        if (songsChanged && !trimmedComment.isEmpty) || commentChanged {
            try? await c.playlistService.updateDescription(id: playlistId, description: trimmedComment)
        }
        if coverDirty {
            await applyCoverInPlace(container: c, serverId: serverId, originalSongs: originalSongs)
        }
        // First-track derivation: empty→first-track fills the gradient color (frozen after). Runs after
        // applyCover so a simultaneous re-pick (resolved from the OLD empty first track) is corrected.
        await AddMusicCommitter.deriveFirstTrackCoverIfNeeded(
            wasEmpty: originalSongs.isEmpty,
            firstSong: editSongs.first,
            playlistId: playlistId,
            serverId: serverId,
            container: c,
            colorExtractor: colorExtractor
        )
        await viewModel?.load()
        coverRefreshID = UUID()
        withAnimation(.smooth) { isEditing = false }
    }

    private func applyCoverInPlace(container c: AppContainer, serverId: UUID, originalSongs: [DisplayableSong]) async {
        let manager = PlaylistCoverManager(
            serverState: c.serverState,
            serverService: c.serverService,
            downloadService: c.downloadService,
            artworkImageCache: c.artworkImageCache
        )
        let store = PlaylistCoverStore(modelContainer: c.modelContainer)
        if let shape = selectedGradient {
            // Re-pick → resolve the color from the CURRENT first track (neutral if the playlist is empty).
            let spec = await PlaylistGradientResolver.resolve(
                form: shape,
                firstTrackCoverArtId: originalSongs.first?.coverArtId,
                artworkImageCache: c.artworkImageCache,
                colorExtractor: colorExtractor
            )
            await manager.applyGradientCover(spec, playlistId: playlistId)
            store.save(spec, playlistId: playlistId, serverId: serverId, isUserPicked: true)
            return
        }
        #if os(iOS)
        if photoIsCover, let image = pendingImage, let data = image.jpegData(compressionQuality: 0.85) {
            await manager.applyImageCover(data, playlistId: playlistId)
            // A photo supersedes any gradient choice → drop the stored gradient.
            store.remove(playlistId: playlistId, serverId: serverId)
        }
        #endif
    }

    // MARK: - In-place editable track list (Gate 2 — mirrors the edit sheet's reorder + multi-select remove)

    @ViewBuilder
    private var editableSongRows: some View {
        ForEach(editSongs) { song in
            editTrackRow(song)
                .tag(song.id)
                .listRowBackground(bodyColor)
                .environment(\.colorScheme, dragHandleScheme)
        }
        .onMove { from, to in
            editSongs.move(fromOffsets: from, toOffset: to)
        }
    }

    /// Force the editable rows' color scheme to the theme's luminance so the SYSTEM reorder handles (≡) and
    /// selection circles contrast the themed row background — they render system-grey (low contrast) otherwise.
    /// The rows' own text uses explicit theme colors, so it is unaffected.
    private var dragHandleScheme: ColorScheme {
        theme.isThemed ? (theme.isLight ? .light : .dark) : colorScheme
    }

    private func editTrackRow(_ song: DisplayableSong) -> some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtView(id: song.coverArtId ?? song.id, size: 80, cornerRadius: CassetteCornerRadius.standard)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(headerTextColor)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(headerSecondaryColor)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Multi-select remove: drop the selected tracks from the local working list. NO per-index server delete —
    /// the commit (Gate 3) replaces the whole list atomically (final list = editSongs − selection), so it's
    /// immune to index drift. Mirrors the edit sheet's removeSelectedTracks (Gate B).
    private func removeSelectedTracks() {
        editSongs.removeAll { selectedSongIds.contains($0.id) }
        selectedSongIds.removeAll()
    }

    private func deletePlaylistInPlace(purgeDownloads: Bool) async {
        guard let c = container else { return }
        do {
            try await c.playlistService.deletePlaylist(id: playlistId, purgeDownloads: purgeDownloads)
            dismiss()
        } catch {
            Logger.playlist.error("PlaylistDetailView: in-place delete failed: \(error, privacy: .public)")
            c.toastService.showError("Failed to delete playlist")
        }
    }

    private func loadEditGradientChoice() {
        guard let c = container, let serverId = c.serverState.activeServer?.id else { return }
        if let choice = PlaylistCoverStore(modelContainer: c.modelContainer).choice(playlistId: playlistId, serverId: serverId),
           choice.isUserPicked, let spec = choice.spec {
            selectedGradient = spec.shape
        }
    }

    #if os(iOS)
    /// Defer presenting the crop screen so the picker fully dismisses first (sequential full-screen covers).
    private func presentCrop(_ image: UIImage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            imageToCrop = CroppableImage(image: image)
        }
    }
    #endif

    // MARK: - Header

    private func playlistHeader(vm: PlaylistDetailViewModel?) -> some View {
        VStack(spacing: 0) {
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
                    heroHeight: heroHeight,
                    gradientSpec: gradientSpec,
                    lightMelt: true
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
                            .foregroundStyle(headerTextColor)
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
                    }, isDisabled: resolvedSongs(vm).isEmpty || (vm?.isDownloadingPlaylist == true), accentColor: heroButtonVariant.background, labelColor: heroButtonVariant.foreground)
                    .frame(maxWidth: 220)

                    if vm?.isOffline != true {
                        if let vm {
                            if vm.isDownloadingPlaylist {
                                Button { Task { await vm.cancelPlaylistDownload() } } label: {
                                    Image(systemName: "xmark")
                                        .font(.cassetteCellTitle)
                                        .foregroundStyle(headerTextColor)
                                        .cassetteGlassButton(size: 44)
                                }
                            } else {
                                switch downloadState(for: vm) {
                                case .notDownloaded:
                                    Button { Task { await vm.downloadPlaylist() } } label: {
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
            .padding(.top, CassetteSpacing.m)
            .padding(.bottom, CassetteSpacing.xl)
        }
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
        let liveSong = song.withDownloaded(liveDownloaded)
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
