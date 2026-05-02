// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI

struct AlbumDetailMacOS: View {
    let albumId: String
    let albumName: String
    let coverArtId: String?

    init(albumId: String, albumName: String, coverArtId: String? = nil) {
        self.albumId = albumId
        self.albumName = albumName
        self.coverArtId = coverArtId
    }

    @Environment(\.appContainer) private var container
    @State private var vm: AlbumDetailViewModel?

    var body: some View {
        Group {
            if let vm {
                albumContent(vm)
            } else {
                LoadingStateView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar { albumToolbar }
        .task(id: container?.serverState.isOnline) {
            guard let c = container else { return }
            if vm == nil {
                vm = AlbumDetailViewModel(
                    albumId: albumId,
                    libraryService: c.libraryService,
                    downloadService: c.downloadService,
                    toastService: c.toastService,
                    serverState: c.serverState
                )
            }
            await vm?.load()
        }
    }

    private func albumContent(_ vm: AlbumDetailViewModel) -> some View {
        let songs = vm.songs
        let serverId = container?.serverState.activeServer?.id ?? UUID()
        return VStack(spacing: 0) {
            DetailHeroView(
                coverArtId: vm.coverArtId ?? coverArtId,
                title: vm.albumName.isEmpty ? albumName : vm.albumName,
                primaryLine: vm.artistName,
                secondaryLine: secondaryLine(vm: vm),
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
                        title: "Unable to Load Album",
                        subtitle: error.displayMessage,
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    AlbumSongRows(
                        songs: songs,
                        albumId: albumId,
                        serverId: serverId,
                        downloadingIds: vm.downloadingIds,
                        onTap: { index in
                            Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
                        },
                        onDownload: (vm.isOffline || vm.isDownloadingAlbum) ? nil : { songId in
                            Task { await vm.downloadSong(id: songId) }
                        },
                        onRemoveDownload: { songId in
                            Task { try? await container?.downloadService.remove(songId: songId, serverId: serverId) }
                        }
                    )
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    private func secondaryLine(vm: AlbumDetailViewModel) -> String? {
        var parts: [String] = []
        if let year = vm.year { parts.append(String(year)) }
        if let genre = vm.genre { parts.append(genre) }
        let count = vm.songCount > 0 ? vm.songCount : vm.songs.count
        if count > 0 { parts.append("\(count) track\(count == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var albumToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if vm?.isDownloadingAlbum == true {
                Button {
                    Task { await vm?.cancelAlbumDownload() }
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    Task { await vm?.downloadAlbum() }
                } label: {
                    Label("Download Album", systemImage: "arrow.down.circle")
                }
                .disabled(vm?.isOffline == true || container?.serverState.isOnline != true)
            }
        }
    }
}
#endif
