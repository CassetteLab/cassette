// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData
import OSLog
#if os(iOS)
import PhotosUI
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
    @Query private var allDownloadedTracks: [DownloadedTrack]
    @State private var viewModel: PlaylistDetailViewModel?
    @State private var dominantColor: Color = .clear
    @State private var isLightBackground: Bool = false
    @State private var showDeleteAlert = false

    // Inline edit mode
    @State private var isEditing = false
    @State private var editName: String = ""
    @State private var editDescription: String = ""
    @State private var isSaving = false
    @State private var coverRefreshID = UUID()
    @AppStorage("coverArtUploadVersion") private var coverArtUploadVersion = 0

    #if os(iOS)
    @State private var pendingImage: UIImage?
    @State private var showImageOptions = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

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
                        onRemoveDownload: { songId in
                            Task { try? await container?.downloadService.remove(songId: songId, serverId: serverId) }
                        },
                        onRemove: (isEditing && !vm.isOffline) ? { index in
                            Task { await vm.removeTrack(at: index) }
                        } : nil,
                        onReorder: (isEditing && !vm.isOffline) ? { source, destination in
                            Task { await vm.moveTracks(from: source, to: destination) }
                        } : nil
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
        .navigationTitle(isEditing ? "" : (viewModel?.name ?? initialName))
        .navigationBarTitleDisplayModeInline()
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
        #if os(iOS)
        .confirmationDialog("Change Cover Art", isPresented: $showImageOptions, titleVisibility: .visible) {
            Button("Choose from Library") { showPhotoPicker = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take a Photo") { showCamera = true }
            }
            Button("Browse Files") { showFilePicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: $pendingImage)
                .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.jpeg, .png, .heic, .webP],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                pendingImage = UIImage(data: data)
            }
        }
        .task(id: selectedPhotoItem) {
            guard let item = selectedPhotoItem else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                pendingImage = UIImage(data: data)
            }
            selectedPhotoItem = nil
        }
        #endif
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
        .cassetteZoomTransition(sourceID: zoomSourceId, in: zoomNamespace)
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
            Logger.playlist.debug("[DBG] uploadCover: viewModel?.coverArtId='\(self.viewModel?.coverArtId ?? "<nil>", privacy: .public)'")
            if let artId = viewModel?.coverArtId {
                Logger.playlist.debug("[DBG] uploadCover: invalidating artId='\(artId, privacy: .public)'")
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

    // MARK: - Download state helpers

    private func downloadedPlaylistTracksCount(in songs: [DisplayableSong]) -> Int {
        let downloadedIds = Set(allDownloadedTracks.map(\.songId))
        return songs.filter { downloadedIds.contains($0.id) }.count
    }

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

            VStack(spacing: CassetteSpacing.s) {
                if isEditing {
                    TextField("Playlist name", text: $editName)
                        .font(.cassetteDetailTitle)
                        .foregroundStyle(headerTextColor)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, CassetteSpacing.l)
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
            }
            .padding(.horizontal, CassetteSpacing.l)

            if !isEditing {
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
                        let total = vm.songs.count
                        let downloaded = downloadedPlaylistTracksCount(in: vm.songs)
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
                                    .tint(Color.cassetteAccent)
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
                size: 220,
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

    @Query private var downloadedTracks: [DownloadedTrack]

    init(songs: [DisplayableSong], serverId: UUID, downloadingIds: Set<String> = [], titleColor: Color = .primary, secondaryColor: Color = .secondary, onTap: @escaping (Int) -> Void, onDownload: ((String) -> Void)? = nil, onRemoveDownload: ((String) -> Void)? = nil, onRemove: ((Int) -> Void)? = nil, onReorder: ((IndexSet, Int) -> Void)? = nil) {
        self.songs = songs
        self.downloadingIds = downloadingIds
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.onTap = onTap
        self.onDownload = onDownload
        self.onRemoveDownload = onRemoveDownload
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
            albumId: song.albumId,
            albumName: song.albumName,
            artistId: song.artistId,
            genre: song.genre,
            duration: song.duration,
            trackNumber: song.trackNumber,
            isDownloaded: liveDownloaded,
            coverArtId: song.coverArtId,
            audioFormat: song.audioFormat
        )
        let isDownloading = downloadingIds.contains(song.id)
        let downloadAction: (() -> Void)? = (liveDownloaded || isDownloading) ? nil : onDownload.map { action in { action(song.id) } }
        let removeAction: (() -> Void)? = liveDownloaded ? onRemoveDownload.map { action in { action(song.id) } } : nil
        HStack(spacing: 0) {
            SongRow(song: liveSong, index: index + 1, showCoverArt: true, titleColor: titleColor, secondaryColor: secondaryColor, onDownload: downloadAction, onRemoveDownload: removeAction, isDownloading: isDownloading)
                .contentShape(Rectangle())
                .onTapGesture { onTap(index) }
            if onReorder != nil {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16))
                    .foregroundStyle(CassetteColors.textTertiary)
                    .padding(.leading, CassetteSpacing.s)
                    .padding(.trailing, CassetteSpacing.m)
            }
        }
        .listRowBackground(Color.clear)
        #if os(macOS)
        .listRowSeparator(.hidden)
        #endif
    }
}
