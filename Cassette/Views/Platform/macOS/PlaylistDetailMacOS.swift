// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import OSLog
import SwiftSonic
import SwiftUI

struct PlaylistDetailMacOS: View {
    let playlistId: String
    let name: String
    let coverArtId: String?
    var showBackButton: Bool = true

    init(playlistId: String, name: String, coverArtId: String? = nil, showBackButton: Bool = true) {
        self.playlistId = playlistId
        self.name = name
        self.coverArtId = coverArtId
        self.showBackButton = showBackButton
    }

    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PlaylistDetailViewModel?
    @State private var showDeleteAlert = false
    @State private var showDeletePlaylistConfirm = false
    @State private var showEditSheet = false
    @State private var showAddMusic = false
    @State private var songToAddToPlaylist: DisplayableSong?

    var body: some View {
        Group {
            if let vm {
                playlistContent(vm)
            } else {
                LoadingStateView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar { playlistToolbar }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .alert("Remove downloaded playlist?", isPresented: $showDeleteAlert) {
            Button("Remove", role: .destructive) { Task { await vm?.deleteDownload() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The audio files will be deleted from this device.")
        }
        .deletePlaylistConfirmation(
            playlistName: vm?.name ?? name,
            isPresented: $showDeletePlaylistConfirm,
            hasDownloads: vm?.songs.contains { $0.isDownloaded } ?? false
        ) { purgeDownloads in
            Task { await deletePlaylistMacOS(purgeDownloads: purgeDownloads) }
        }
        .sheet(isPresented: $showEditSheet) {
            PlaylistEditSheet(
                initialName: vm?.name ?? name,
                initialDescription: vm?.playlistDetail?.comment ?? "",
                onSave: { newName, newDesc in
                    Task { await saveEdit(name: newName, description: newDesc) }
                }
            )
        }
        .sheet(isPresented: $showAddMusic) {
            if let vm, let c = container, let serverId = c.serverState.activeServer?.id {
                AddMusicSheet(
                    playlistName: vm.name.isEmpty ? name : vm.name,
                    existingTrackIds: vm.songs.map(\.id)
                ) { added in
                    await AddMusicCommitter.commit(
                        addedSongs: added,
                        playlistId: playlistId,
                        serverId: serverId,
                        existingTrackIds: vm.songs.map(\.id),
                        currentComment: vm.playlistDetail?.comment ?? "",
                        container: c,
                        colorExtractor: colorExtractor
                    )
                    await vm.load()
                }
                .environment(colorExtractor)
                .environment(c.artworkImageCache)
                .environment(\.appContainer, c)
                .frame(minWidth: 480, minHeight: 580)
            }
        }
        .task(id: container?.serverState.isOnline) {
            guard let c = container else { return }
            if vm == nil {
                vm = PlaylistDetailViewModel(
                    playlistId: playlistId,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    playlistService: c.playlistService,
                    toastService: c.toastService,
                    serverState: c.serverState
                )
            }
            await vm?.load()
        }
    }

    private func playlistContent(_ vm: PlaylistDetailViewModel) -> some View {
        let songs = vm.songs
        let serverId = container?.serverState.activeServer?.id ?? UUID()
        return VStack(spacing: 0) {
            DetailHeroView(
                coverArtId: vm.coverArtId ?? coverArtId,
                title: vm.name.isEmpty ? name : vm.name,
                primaryLine: vm.owner,
                secondaryLine: songs.isEmpty ? nil : "\(songs.count) track\(songs.count == 1 ? "" : "s")",
                primaryAction: {
                    Task { try? await container?.playerService.play(tracks: songs, startIndex: 0) }
                },
                secondaryAction: {
                    Task {
                        try? await container?.playerService.playShuffled(tracks: songs)
                    }
                }
            )
            .frame(maxWidth: .infinity)

            List {
                if vm.isLoading && songs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if songs.isEmpty, let error = vm.error {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Playlist",
                        subtitle: error.displayMessage,
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    PlaylistSongRows(
                        songs: songs,
                        serverId: serverId,
                        downloadingIds: vm.downloadingIds,
                        onTap: { index in
                            Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
                        },
                        onDownload: (vm.isOffline || vm.isDownloadingPlaylist) ? nil : { songId in
                            Task { await vm.downloadSong(id: songId) }
                        },
                        onRemoveDownload: { songId in
                            Task { try? await container?.downloadService.remove(songId: songId, serverId: serverId) }
                        },
                        onRemove: vm.isOffline ? nil : { index in
                            Task { await vm.removeTrack(at: index) }
                        },
                        onReorder: vm.isOffline ? nil : { source, dest in
                            Task { await vm.moveTracks(from: source, to: dest) }
                        },
                        onAddToPlaylist: { song in songToAddToPlaylist = song }
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await vm.load() }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: CassetteMacOSLayout.playerBarReservedHeight / 2)
            }
            .sheet(item: $songToAddToPlaylist) { song in
                AddToPlaylistSheet(song: song)
            }
        }
    }

    private func saveEdit(name newName: String, description: String) async {
        guard let c = container else { return }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalDesc = (vm?.playlistDetail?.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedName.isEmpty && trimmedName != (vm?.name ?? name) {
            do {
                try await c.playlistService.renamePlaylist(id: playlistId, newName: trimmedName)
                vm?.name = trimmedName
            } catch {
                Logger.playlist.warning("PlaylistDetailMacOS: rename failed: \(error)")
                c.toastService.showError("Failed to rename playlist")
            }
        }

        if trimmedDesc != originalDesc {
            do {
                try await c.playlistService.updateDescription(id: playlistId, description: trimmedDesc)
            } catch {
                Logger.playlist.warning("PlaylistDetailMacOS: description update failed: \(error)")
                c.toastService.showError("Failed to update description")
            }
        }

        await vm?.load()
    }

    private func deletePlaylistMacOS(purgeDownloads: Bool) async {
        guard let c = container else { return }
        do {
            try await c.playlistService.deletePlaylist(id: playlistId, purgeDownloads: purgeDownloads)
            postPlaylistDeleted()
            dismiss()
        } catch {
            Logger.playlist.error("PlaylistDetailMacOS: delete failed: \(error, privacy: .public)")
            c.toastService.showError("Failed to delete playlist")
        }
    }

    @ToolbarContentBuilder
    private var playlistToolbar: some ToolbarContent {
        if showBackButton {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.borderless)
                .help("Back")
            }
            .cassetteSharedBackgroundVisibility(.hidden)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showAddMusic = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .cassetteGlassButton(size: 28)
            }
            .buttonStyle(.borderless)
            .disabled(vm?.isOffline == true || container?.serverState.isOnline != true || vm?.playlistDetail == nil)
            .help("Add Music")
        }
        .cassetteSharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .primaryAction) {
            Button {
                showEditSheet = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .cassetteGlassButton(size: 28)
            }
            .buttonStyle(.borderless)
            .disabled(vm?.isOffline == true || container?.serverState.isOnline != true || vm?.playlistDetail == nil)
            .help("Edit Playlist")
        }
        .cassetteSharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .primaryAction) {
            if vm?.isDownloadingPlaylist == true {
                Button {
                    Task { await vm?.cancelPlaylistDownload() }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.borderless)
                .help("Cancel Download")
            } else if vm?.songs.contains(where: { $0.isDownloaded }) == true {
                // Downloaded → this button manages the LOCAL copy (free space) — distinct from the trash, which
                // deletes the playlist itself. Reuses the existing "Remove downloaded playlist?" confirmation.
                Button {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.borderless)
                .help("Remove Download")
            } else {
                Button {
                    Task { await vm?.downloadPlaylist() }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.borderless)
                .disabled(vm?.isOffline == true || container?.serverState.isOnline != true)
                .help("Download Playlist")
            }
        }
        .cassetteSharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                showDeletePlaylistConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .cassetteGlassButton(size: 28)
            }
            .buttonStyle(.borderless)
            .help("Delete Playlist")
        }
        .cassetteSharedBackgroundVisibility(.hidden)
    }
}

private struct PlaylistEditSheet: View {
    let initialName: String
    let initialDescription: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editName: String = ""
    @State private var editDescription: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Playlist")
                .font(.title3.weight(.semibold))

            Form {
                TextField("Name", text: $editName)
                TextField("Description", text: $editDescription, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    onSave(editName, editDescription)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 340)
        .onAppear {
            editName = initialName
            editDescription = initialDescription
        }
    }
}
#endif
