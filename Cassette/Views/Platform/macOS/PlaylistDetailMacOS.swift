// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
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
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PlaylistDetailViewModel?
    @State private var showDeleteAlert = false

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
                        if container?.playerState.isShuffled != true {
                            await container?.playerService.toggleShuffle()
                        }
                        try? await container?.playerService.play(tracks: songs, startIndex: 0)
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
                        }
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await vm.load() }
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
                .buttonStyle(.plain)
                .help("Back")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            if vm?.isDownloadingPlaylist == true {
                Button {
                    Task { await vm?.cancelPlaylistDownload() }
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    Task { await vm?.downloadPlaylist() }
                } label: {
                    Label("Download Playlist", systemImage: "arrow.down.circle")
                }
                .disabled(vm?.isOffline == true || container?.serverState.isOnline != true)
            }
        }

        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
            .disabled(!(vm?.songs.contains { $0.isDownloaded } ?? false))
        }
    }
}
#endif
