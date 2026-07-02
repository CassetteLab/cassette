// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI

struct AlbumDetailMacOS: View {
    let albumId: String
    let albumName: String
    let coverArtId: String?
    var showBackButton: Bool = true

    init(albumId: String, albumName: String, coverArtId: String? = nil, showBackButton: Bool = true) {
        self.albumId = albumId
        self.albumName = albumName
        self.coverArtId = coverArtId
        self.showBackButton = showBackButton
    }

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AlbumDetailViewModel?
    @State private var songToAddToPlaylist: DisplayableSong?

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
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
            if vm?.isDownloadingAlbum == true {
                Button {
                    Task { await vm?.cancelAlbumDownload() }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.borderless)
                .help("Cancel Download")
            } else {
                Button {
                    Task { await vm?.downloadAlbum() }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .cassetteGlassButton(size: 28)
                }
                .buttonStyle(.borderless)
                .disabled(vm?.isOffline == true || container?.serverState.isOnline != true)
                .help("Download Album")
            }
        }
        .cassetteSharedBackgroundVisibility(.hidden)
    }
}
#endif
