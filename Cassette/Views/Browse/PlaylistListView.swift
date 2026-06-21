// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic
import OSLog

struct PlaylistListView: View {
    var zoomNamespace: Namespace.ID? = nil
    @Environment(\.appContainer) private var container
    @State private var viewModel: PlaylistListViewModel?
    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.cassetteAccent)
                }
                .disabled(container?.serverState.isOnline != true)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistSheet { _ in
                Task { await viewModel?.load() }
            }
        }
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = PlaylistListViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: PlaylistListViewModel) -> some View {
        if vm.isLoading && vm.playlists.isEmpty {
            LoadingStateView()
        } else if container?.serverState.isOnline == false && vm.playlists.isEmpty {
            if let serverId = container?.serverState.activeServer?.id {
                OfflinePlaylistContent(serverId: serverId)
            } else {
                EmptyStateView(
                    systemImage: "wifi.slash",
                    title: "You're Offline",
                    subtitle: "Connect to your server to browse playlists."
                )
            }
        } else if let error = vm.error, vm.playlists.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Playlists",
                subtitle: error.displayMessage,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.playlists.isEmpty {
            EmptyStateView(
                systemImage: "list.bullet",
                title: "No Playlists",
                subtitle: "Create playlists on your server to see them here."
            )
        } else {
            List(vm.playlists) { playlist in
                NavigationLink(value: HomeDestination.playlist(playlist)) {
                    OnlinePlaylistRow(
                        playlist: playlist,
                        namespace: zoomNamespace,
                        onActionCompleted: { Task { await vm.load() } }
                    )
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - Online playlist row

private struct OnlinePlaylistRow: View {
    let playlist: Playlist
    var namespace: Namespace.ID? = nil
    var onActionCompleted: (() -> Void)? = nil

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtCard(id: playlist.coverArt ?? playlist.id, size: 56)
                .cassetteMatchedTransitionSource(id: playlist.id, in: namespace)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.cassetteCellTitle)
                    .lineLimit(1)
                Text("\(playlist.songCount) track\(playlist.songCount == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .task(id: playlist.id) {
            coverImage = await artworkImageCache.load(coverArtId: playlist.coverArt ?? playlist.id)
        }
        .collectionContextMenu(
            itemType: .playlist,
            itemId: playlist.id,
            displayName: playlist.name,
            displaySubtitle: "Playlist",
            coverArtId: playlist.coverArt,
            coverImage: coverImage,
            onDelete: { showDeleteConfirm = true }
        )
        .confirmationDialog(
            "Delete \"\(playlist.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    guard let container else { return }
                    do {
                        // The service deletes server-side first and rolls its own cache back on failure, so it
                        // is safe to refresh the (server-fresh) list only AFTER a confirmed success.
                        try await container.playlistService.deletePlaylist(id: playlist.id)
                        onActionCompleted?()
                        container.toastService.showConfirmation("Playlist deleted")
                    } catch {
                        // Server refused / unreachable: surface it and leave the playlist in place. Do NOT
                        // refresh or remove anything locally — the deletion never happened.
                        Logger.playlist.error("[PLAYLIST] delete failed id=\(playlist.id, privacy: .public): \(error, privacy: .public)")
                        container.toastService.showError("Couldn't delete playlist. Please try again.")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the playlist. This action cannot be undone.")
        }
    }
}

// MARK: - Offline Playlists

private struct OfflinePlaylistContent: View {
    let serverId: UUID
    @Query private var playlists: [DownloadedPlaylist]

    init(serverId: UUID) {
        self.serverId = serverId
        let sid = serverId
        _playlists = Query(
            filter: #Predicate<DownloadedPlaylist> { playlist in playlist.serverId == sid },
            sort: [SortDescriptor(\DownloadedPlaylist.name)]
        )
    }

    var body: some View {
        if playlists.isEmpty {
            EmptyStateView(
                systemImage: "wifi.slash",
                title: "You're Offline",
                subtitle: "No downloaded playlists available. Download playlists while online to listen offline."
            )
        } else {
            List {
                Section("Downloaded Playlists") {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: HomeDestination.playlistById(id: playlist.playlistId, name: playlist.name, coverArtId: playlist.coverArtId)) {
                            OfflinePlaylistRow(playlist: playlist)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct OfflinePlaylistRow: View {
    let playlist: DownloadedPlaylist

    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtCard(id: playlist.coverArtId ?? playlist.playlistId, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.cassetteCellTitle)
                    .lineLimit(1)
                Text("\(playlist.tracksCount) track\(playlist.tracksCount == 1 ? "" : "s")")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
        .task(id: playlist.playlistId) {
            coverImage = await artworkImageCache.load(coverArtId: playlist.coverArtId ?? playlist.playlistId)
        }
        .collectionContextMenu(
            itemType: .playlist,
            itemId: playlist.playlistId,
            displayName: playlist.name,
            displaySubtitle: "Playlist",
            coverArtId: playlist.coverArtId,
            coverImage: coverImage
        )
    }
}
