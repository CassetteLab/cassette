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
        let pid = playlist.playlistId
        _downloadedPlaylistMatches = Query(filter: #Predicate<DownloadedPlaylist> { $0.playlistId == pid })
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
        let pid = playlistId
        _downloadedPlaylistMatches = Query(filter: #Predicate<DownloadedPlaylist> { $0.playlistId == pid })
        _dominantColor = State(initialValue: initialDominantColor)
        _isLightBackground = State(initialValue: initialDominantColor == .clear ? false : initialDominantColor.luminance > 0.6)
    }

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: PlaylistDetailViewModel?
    @State private var dominantColor: Color = .clear
    @State private var isLightBackground: Bool = false
    @State private var showDeleteAlert = false
    @State private var songToAddToPlaylist: DisplayableSong?

    // Inline edit mode
    @State private var isEditing = false
    @State private var editName: String = ""
    @State private var editDescription: String = ""
    @State private var isSaving = false
    @State private var coverRefreshID = UUID()
    @AppStorage("coverArtUploadVersion") private var coverArtUploadVersion = 0

    // View-level offline backstop: sources the song list straight from SwiftData when the
    // view model produced nothing (empty-success or error). Mirrors AlbumDetailView's
    // downloaded fallback so a downloaded playlist stays readable independent of the
    // network, the VM, and connectivity detection. Keyed on playlistId here; serverId is
    // applied at read time since it isn't known at init.
    @Query private var downloadedPlaylistMatches: [DownloadedPlaylist]
    @Query private var allDownloadedTracks: [DownloadedTrack]

    #if os(iOS)
    private enum CoverPickerSource: Identifiable {
        case library, camera, files
        var id: Self { self }
    }

    @State private var pendingImage: UIImage?
    @State private var showImageOptions = false
    @State private var coverPickerSource: CoverPickerSource?
    #endif

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
                        onRemove: (isEditing && !vm.isOffline) ? { index in
                            Task { await vm.removeTrack(at: index) }
                        } : nil,
                        onReorder: (isEditing && !vm.isOffline) ? { source, destination in
                            Task { await vm.moveTracks(from: source, to: destination) }
                        } : nil,
                        onContextRemove: !vm.isOffline ? { index in
                            Task { await vm.removeTrack(at: index) }
                        } : nil,
                        onAddToPlaylist: { song in songToAddToPlaylist = song }
                    )
                }
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        #endif
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
        .background(
            PlaylistThemedBackground(
                coverArtId: viewModel?.coverArtId ?? coverArtId ?? playlistId,
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
        #if os(iOS)
        .fullScreenCover(item: $coverPickerSource) { source in
            switch source {
            case .library:
                ImagePickerController(sourceType: .photoLibrary, onPick: { pendingImage = $0 }, onCancel: {})
                    .ignoresSafeArea()
            case .camera:
                ImagePickerController(sourceType: .camera, onPick: { pendingImage = $0 }, onCancel: {})
                    .ignoresSafeArea()
            case .files:
                DocumentImagePicker(onPick: { pendingImage = $0 })
                    .ignoresSafeArea()
            }
        }
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
        .cassetteZoomTransition(sourceID: zoomSourceId, in: zoomNamespace)
        #if os(iOS)
        .sheet(isPresented: $showImageOptions) {
            VStack(spacing: 0) {
                Text("Change Cover Art")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CassetteColors.textSecondary)
                    .padding(.top, CassetteSpacing.l)
                    .padding(.bottom, CassetteSpacing.m)

                Divider()

                coverPickerRow(icon: "photo.on.rectangle", label: "Choose from Library") {
                    showImageOptions = false
                    coverPickerSource = .library
                }

                Divider().padding(.leading, 56)

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    coverPickerRow(icon: "camera.fill", label: "Take a Photo") {
                        showImageOptions = false
                        coverPickerSource = .camera
                    }
                    Divider().padding(.leading, 56)
                }

                coverPickerRow(icon: "folder.fill", label: "Browse Files") {
                    showImageOptions = false
                    coverPickerSource = .files
                }
            }
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
        }
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if isEditing {
                Button("Cancel") { cancelEdit() }
                    .disabled(isSaving)
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if isSaving {
                ProgressView().controlSize(.small)
            } else if isEditing {
                Button("Done") {
                    Task { await saveInlineEdit() }
                }
                .fontWeight(.semibold)
            } else {
                Button {
                    enterEditMode()
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(CassetteColors.accent)
                }
                .disabled(container?.serverState.isOnline != true || viewModel?.playlistDetail == nil)
            }
        }
    }

    // MARK: - Edit mode

    private func enterEditMode() {
        editName = viewModel?.name ?? initialName
        editDescription = viewModel?.playlistDetail?.comment ?? ""
        #if os(iOS)
        pendingImage = nil
        #endif
        isEditing = true
    }

    private func cancelEdit() {
        editName = ""
        editDescription = ""
        #if os(iOS)
        pendingImage = nil
        #endif
        isEditing = false
    }

    private func saveInlineEdit() async {
        guard let vm = viewModel, let c = container else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalDesc = (vm.playlistDetail?.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedName.isEmpty && trimmedName != vm.name {
            do {
                try await c.playlistService.renamePlaylist(id: playlistId, newName: trimmedName)
                vm.name = trimmedName
            } catch {
                Logger.playlist.warning("PlaylistDetailView: rename failed: \(error)")
                c.toastService.showError("Failed to rename playlist")
            }
        }

        if trimmedDesc != originalDesc {
            do {
                try await c.playlistService.updateDescription(id: playlistId, description: trimmedDesc)
            } catch {
                Logger.playlist.warning("PlaylistDetailView: description update failed: \(error)")
                c.toastService.showError("Failed to update description")
            }
        }

        #if os(iOS)
        if let image = pendingImage {
            await uploadCoverImage(image, container: c)
        }
        #endif

        isEditing = false
        Task { await vm.load() }
    }

    #if os(iOS)
    private func uploadCoverImage(_ image: UIImage, container: AppContainer) async {
        guard let jpegData = image.jpegData(compressionQuality: 0.85),
              let snapshot = container.serverState.activeServer,
              let baseURL = URL(string: snapshot.baseURL) else { return }
        do {
            let creds = try await container.serverService.activeCredentials()
            let api = NavidromeNativeAPI(transport: CustomHeadersTransport(headers: creds.customHeaders))
            Logger.playlist.debug("Navidrome auth: requesting JWT for user=\(snapshot.username, privacy: .private)")
            let token = try await api.authenticate(
                baseURL: baseURL,
                username: snapshot.username,
                password: creds.password
            )
            Logger.playlist.debug("Navidrome auth: JWT obtained")
            Logger.playlist.debug("Upload playlist cover: POST /api/playlist/\(playlistId, privacy: .public)/image, cf_headers=\(!creds.customHeaders.isEmpty)")
            try await api.uploadPlaylistCover(
                baseURL: baseURL,
                token: token,
                playlistId: playlistId,
                imageData: jpegData,
                mimeType: "image/jpeg"
            )
            Logger.playlist.debug("Upload playlist cover: success")
            Logger.playlist.debug("uploadCover: viewModel?.coverArtId='\(self.viewModel?.coverArtId ?? "<nil>", privacy: .public)'")
            if let artId = viewModel?.coverArtId {
                Logger.playlist.debug("uploadCover: invalidating artId='\(artId, privacy: .public)'")
                await container.artworkImageCache.invalidate(for: artId)
            }
            if let vm = viewModel {
                await vm.load()
                container.pinService.updateCoverArtId(itemType: .playlist, itemId: playlistId, newCoverArtId: vm.coverArtId)
            }
            coverRefreshID = UUID()
            coverArtUploadVersion += 1
            pendingImage = nil
        } catch {
            Logger.playlist.warning("PlaylistDetailView: cover image upload failed: \(error)")
        }
    }

    private func coverPickerRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CassetteSpacing.m) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(CassetteColors.accent)
                    .frame(width: 28)
                    .padding(.leading, CassetteSpacing.l)
                Text(label)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(CassetteColors.textPrimary)
                Spacer()
            }
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #endif

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
            isLightBackground = color.luminance > 0.6
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
            // Cover art
            Group {
                #if os(iOS)
                if isEditing {
                    ZStack {
                        if let pending = pendingImage {
                            Image(uiImage: pending)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: 220, height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.large))
                        } else {
                            coverArtContent(vm: vm)
                        }
                        RoundedRectangle(cornerRadius: CassetteCornerRadius.large)
                            .fill(Color.black.opacity(0.4))
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 220, height: 220)
                    .onTapGesture { showImageOptions = true }
                } else {
                    coverArtContent(vm: vm)
                }
                #else
                coverArtContent(vm: vm)
                #endif
            }
            .padding(.top, CassetteSpacing.xxl)

            VStack(spacing: 0) {
                if isEditing {
                    TextField("Playlist name", text: $editName)
                        .font(.cassetteDetailTitle)
                        .foregroundStyle(headerTextColor)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, CassetteSpacing.l)
                        .padding(.bottom, CassetteSpacing.s)
                    TextField("Add a description...", text: $editDescription, axis: .vertical)
                        .font(.cassetteCellSubtitle)
                        .foregroundStyle(headerSecondaryColor)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(.horizontal, CassetteSpacing.l)
                } else {
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
            }
            .padding(.horizontal, CassetteSpacing.l)

            if !isEditing {
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
        if initialCoverImage == nil && vm?.coverArtId == nil && coverArtId == nil {
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
