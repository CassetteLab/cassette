// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import OSLog
#if os(iOS)
import UniformTypeIdentifiers
#endif

/// Apple-Music-style modal playlist editor: X (cancel) / ✓ (commit), a cover-picker carousel
/// (`PlaylistCoverPicker`, pre-selected from the stored gradient choice), title, description (↔ playlist
/// `comment`), the track list, and a trash (delete) action. Phase 2b/A: metadata + cover re-pick; the track
/// list is read-only here (reorder + multi-select remove land in Phase B). Cross-platform-ready; only the
/// photo-picker plumbing and the bottom-bar placement are iOS-gated.
struct EditPlaylistSheet: View {
    let playlistId: String
    let serverId: UUID
    let currentName: String
    let currentComment: String
    let currentCoverArtId: String?
    let songs: [DisplayableSong]
    /// Called after a successful commit so the detail view reloads + refreshes its cover.
    var onCommitted: () -> Void = {}
    /// Called after a successful delete so the detail view can pop.
    var onDeleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor

    @State private var editName: String = ""
    @State private var editComment: String = ""
    /// Local, mutable working copy of the track list — reorder (drag) and multi-select remove both mutate this;
    /// the commit does ONE atomic full-list replace (createPlaylist replace) if it differs from `songs`.
    @State private var editSongs: [DisplayableSong] = []
    /// Multi-select set (song ids) for the remove action.
    @State private var selectedSongIds: Set<String> = []
    @State private var selectedGradient: PlaylistGradientShape?
    @State private var coverDirty = false
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var loaded = false

    #if os(iOS)
    @State private var pendingImage: UIImage?
    @State private var showImageOptions = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showFilePicker = false
    #endif

    var body: some View {
        NavigationStack {
            List(selection: $selectedSongIds) {
                Section {
                    PlaylistCoverPicker(
                        selectedGradient: selectedGradient,
                        isPhotoSelected: hasPhoto,
                        photoPreview: photoPreviewImage,
                        showsPhotoOption: showsPhotoOption,
                        leadingLabel: "Current",
                        leadingCoverArtId: currentCoverArtId ?? playlistId,
                        onSelectLeading: {
                            selectedGradient = nil
                            coverDirty = true
                            #if os(iOS)
                            pendingImage = nil
                            #endif
                        },
                        onSelectPhoto: {
                            selectedGradient = nil
                            coverDirty = true
                            #if os(iOS)
                            showImageOptions = true
                            #endif
                        },
                        onSelectGradient: { shape in
                            selectedGradient = shape
                            coverDirty = true
                            #if os(iOS)
                            pendingImage = nil
                            #endif
                        }
                    )
                    .listRowInsets(EdgeInsets(top: CassetteSpacing.s, leading: CassetteSpacing.m,
                                              bottom: CassetteSpacing.s, trailing: CassetteSpacing.m))
                }

                Section("Name") {
                    TextField("Playlist Name", text: $editName)
                }
                Section("Description") {
                    TextField("Add a description…", text: $editComment, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Songs") {
                    ForEach(editSongs) { song in
                        trackRow(song)
                            .tag(song.id)
                    }
                    .onMove { from, to in
                        editSongs.move(fromOffsets: from, toOffset: to)
                    }
                }
            }
            .navigationTitle("Edit Playlist")
            .navigationBarTitleDisplayModeInline()
            // Always-on edit mode so the Songs rows show drag-reorder handles (and, in B2, selection circles).
            .environment(\.editMode, .constant(.active))
            .toolbar { toolbar }
            .confirmationDialog("Delete \"\(currentName)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await deletePlaylist() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the playlist everywhere, including any downloaded copy.")
            }
            #if os(iOS)
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
                ImagePickerController(sourceType: .photoLibrary, onPick: { pendingImage = $0 }, onCancel: {})
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePickerController(sourceType: .camera, onPick: { pendingImage = $0 }, onCancel: {})
                    .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.jpeg, .png, .heic, .webP], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { pendingImage = UIImage(data: data) }
            }
            #endif
            .task {
                guard !loaded else { return }
                loaded = true
                editName = currentName
                editComment = currentComment
                editSongs = songs
                loadCurrentChoice()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await commit() } } label: { Image(systemName: "checkmark").fontWeight(.semibold) }
                    .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Image(systemName: "trash")
            }
            .disabled(isSaving)
            Spacer()
            // Multi-select REMOVE TRACKS (distinct from the trash above = delete the whole playlist). Only the
            // local working list is mutated here; the commit persists it via the one atomic replace.
            if !selectedSongIds.isEmpty {
                Button(role: .destructive) { removeSelectedTracks() } label: {
                    Text("Remove \(selectedSongIds.count)")
                }
                .disabled(isSaving)
            }
        }
        #endif
    }

    private func trackRow(_ song: DisplayableSong) -> some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtView(id: song.coverArtId ?? song.id, size: 80, cornerRadius: CassetteCornerRadius.standard)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.cassetteCellTitle).lineLimit(1)
                if let artist = song.artist {
                    Text(artist).font(.cassetteCellSubtitle).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    /// Multi-select remove: drop the selected tracks from the local working list. NO per-index server delete —
    /// the commit replaces the whole list atomically (final list = `editSongs` minus the selection), so it's
    /// immune to index drift. Distinct from the detail-view swipe-remove (Phase 1) and the trash (delete
    /// playlist).
    private func removeSelectedTracks() {
        editSongs.removeAll { selectedSongIds.contains($0.id) }
        selectedSongIds.removeAll()
    }

    // MARK: - State

    private var hasPhoto: Bool {
        #if os(iOS)
        return pendingImage != nil
        #else
        return false
        #endif
    }
    private var showsPhotoOption: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
    private var photoPreviewImage: PlatformImage? {
        #if os(iOS)
        return pendingImage
        #else
        return nil
        #endif
    }

    private func loadCurrentChoice() {
        guard let c = container else { return }
        if let choice = PlaylistCoverStore(modelContainer: c.modelContainer).choice(playlistId: playlistId, serverId: serverId),
           choice.isUserPicked, let spec = choice.spec {
            selectedGradient = spec.shape
        }
    }

    // MARK: - Commit / cover / delete

    private func commit() async {
        guard let c = container else { return }
        isSaving = true
        defer { isSaving = false }

        // Compare trimmed-vs-trimmed so incidental whitespace (e.g. a server name with a trailing space, or
        // a whitespace-only description edit) never triggers a no-op server write.
        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComment = editComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let commentChanged = trimmedComment != currentComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let songsChanged = editSongs.map(\.id) != songs.map(\.id)

        if !trimmedName.isEmpty && trimmedName != currentName.trimmingCharacters(in: .whitespacesAndNewlines) {
            try? await c.playlistService.renamePlaylist(id: playlistId, newName: trimmedName)
        }
        // Atomic full-list replace — the SINGLE track-mutation path (reorder + multi-select remove). The
        // replace carries only playlistId + songIds: the name is preserved (omitted), comment is NOT a param.
        if songsChanged {
            try? await c.playlistService.reorderTracks(playlistId: playlistId, orderedSongIds: editSongs.map(\.id))
        }
        // R1 guard: re-assert the comment AFTER the replace (it doesn't survive createPlaylist). Re-assert a
        // non-empty comment even if unchanged; always write a changed comment (edit/clear). One write covers
        // the guard + a simultaneous description edit. NO name re-assert (omitted = unchanged).
        if (songsChanged && !trimmedComment.isEmpty) || commentChanged {
            try? await c.playlistService.updateDescription(id: playlistId, description: trimmedComment)
        }
        if coverDirty {
            await applyCover(container: c)
        }
        // Dismiss first, then notify — mirrors deletePlaylist(). The sheet's dismiss and the detail view's
        // dismiss (inside onCommitted/onDeleted) are independent environments, so this ordering is safe.
        dismiss()
        onCommitted()
    }

    private func applyCover(container c: AppContainer) async {
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
                firstTrackCoverArtId: songs.first?.coverArtId,
                artworkImageCache: c.artworkImageCache,
                colorExtractor: colorExtractor
            )
            await manager.applyGradientCover(spec, playlistId: playlistId)
            store.save(spec, playlistId: playlistId, serverId: serverId, isUserPicked: true)
            return
        }
        #if os(iOS)
        if let image = pendingImage, let data = image.jpegData(compressionQuality: 0.85) {
            await manager.applyImageCover(data, playlistId: playlistId)
            // A photo supersedes any gradient choice → drop the stored gradient.
            store.remove(playlistId: playlistId, serverId: serverId)
        }
        #endif
        // Leading "Current" with no photo → no cover change (no cover-delete API exists).
    }

    private func deletePlaylist() async {
        guard let c = container else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await c.playlistService.deletePlaylist(id: playlistId)
            dismiss()
            onDeleted()
        } catch {
            Logger.playlist.error("EditPlaylistSheet: delete failed: \(error)")
            c.toastService.showError("Failed to delete playlist")
        }
    }
}
