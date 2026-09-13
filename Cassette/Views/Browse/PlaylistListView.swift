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
            syncFilter()
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
            await viewModel?.loadBestOf()
        }
        // The filter is persisted per server, so it changes both when the user edits it and when
        // they switch servers. Re-reading the snapshot covers both without a reload: the list is
        // already in hand, only what is drawn from it changes.
        .onChange(of: filterIdentity) { syncFilter() }
        // Deleting a playlist from a detail surface posts this — reload so the list reflects it on return,
        // without a blanket `.onAppear` reload (which would re-fetch on every navigation).
        .onReceive(NotificationCenter.default.publisher(for: .cassettePlaylistDeleted)) { _ in
            Task { await viewModel?.load() }
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
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.playlists.isEmpty && vm.bestOfPlaylists.isEmpty {
            EmptyStateView(
                systemImage: "list.bullet",
                title: "No Playlists",
                subtitle: "Create playlists on your server to see them here."
            )
        } else if vm.isEmptyBecauseFiltered {
            // Distinct from "No Playlists" on purpose: the list is empty because of a choice the
            // user made, possibly on another launch, and saying so is what makes it undoable.
            EmptyStateView(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "Nothing To Show",
                subtitle: "Every playlist is hidden by the current filter.",
                action: .init(label: "Show All") { clearFilter() }
            )
        } else {
            List {
                // Derived from the user's stars, not stored on the server — hence its own section rather
                // than being mixed in with the real playlists below.
                if !vm.visibleBestOfPlaylists.isEmpty {
                    Section("Made For You") {
                        ForEach(vm.visibleBestOfPlaylists) { bestOf in
                            NavigationLink(value: HomeDestination.artistBestOf(
                                artistId: bestOf.artistId,
                                artistName: bestOf.artistName,
                                coverArtId: bestOf.coverArtId
                            )) {
                                BestOfPlaylistRow(bestOf: bestOf)
                            }
                        }
                    }
                }
                // Label the server playlists only when there's a derived section above to tell them apart
                // from — on its own the header would just repeat the screen title.
                if vm.visibleBestOfPlaylists.isEmpty {
                    serverPlaylistRows(vm)
                } else if !vm.visiblePlaylists.isEmpty {
                    Section("Playlists") { serverPlaylistRows(vm) }
                }
            }
            .listStyle(.plain)
            .miniPlayerBottomMargin()
            .refreshable {
                await vm.load()
                await vm.loadBestOf()
            }
        }
    }

    @ViewBuilder
    private func serverPlaylistRows(_ vm: PlaylistListViewModel) -> some View {
        ForEach(vm.visiblePlaylists) { playlist in
            NavigationLink(value: HomeDestination.playlist(playlist)) {
                OnlinePlaylistRow(
                    playlist: playlist,
                    namespace: zoomNamespace,
                    onActionCompleted: { Task { await vm.load() } }
                )
            }
        }
    }

    // MARK: - Filter plumbing

    /// What a filter change looks like from here: the server, and its hidden set.
    private var filterIdentity: String {
        let server = container?.serverState.activeServer
        return "\(server?.id.uuidString ?? "none")|\(server?.hiddenPlaylistKinds ?? "")"
    }

    private func syncFilter() {
        let server = container?.serverState.activeServer
        viewModel?.applyFilter(hiddenKinds: server?.hiddenPlaylistKindSet ?? [], serverId: server?.id)
    }

    private func clearFilter() {
        guard let container, let serverId = container.serverState.activeServer?.id else { return }
        Task {
            do {
                try await container.serverService.setHiddenPlaylistKinds(serverId: serverId, kinds: [])
            } catch {
                Logger.playlist.error("[PLAYLIST] could not clear the type filter: \(error, privacy: .public)")
                container.toastService.showError("Couldn't change the filter. Please try again.")
            }
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
    /// Drives the delete dialog's "playlist only / + downloads" choice — present only when the playlist has a
    /// downloaded copy on this device.
    @Query private var downloadedMatches: [DownloadedPlaylist]

    init(playlist: Playlist, namespace: Namespace.ID? = nil, onActionCompleted: (() -> Void)? = nil) {
        self.playlist = playlist
        self.namespace = namespace
        self.onActionCompleted = onActionCompleted
        let pid = playlist.id
        _downloadedMatches = Query(filter: #Predicate<DownloadedPlaylist> { $0.playlistId == pid })
    }

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            PlaylistCoverThumbnail(playlistId: playlist.id, serverId: nil, coverArtId: playlist.coverArt ?? playlist.id, title: playlist.name, size: 56)
                .cassetteMatchedTransitionSource(id: playlist.id, in: namespace)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.cassetteCellTitle)
                    .lineLimit(1)
                Text("\(playlist.songCount) tracks")
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
        .deletePlaylistConfirmation(
            playlistName: playlist.name,
            isPresented: $showDeleteConfirm,
            hasDownloads: !downloadedMatches.isEmpty
        ) { purgeDownloads in
            Task {
                guard let container else { return }
                do {
                    // The service deletes server-side first and rolls its own cache back on failure, so it is
                    // safe to refresh the (server-fresh) list only AFTER a confirmed success.
                    try await container.playlistService.deletePlaylist(id: playlist.id, purgeDownloads: purgeDownloads)
                    onActionCompleted?()
                    container.toastService.showConfirmation("Playlist deleted")
                } catch {
                    // Server refused / unreachable: surface it and leave the playlist in place. Do NOT refresh
                    // or remove anything locally — the deletion never happened.
                    Logger.playlist.error("[PLAYLIST] delete failed id=\(playlist.id, privacy: .public): \(error, privacy: .public)")
                    container.toastService.showError("Couldn't delete playlist. Please try again.")
                }
            }
        }
    }
}

// MARK: - Derived "best of" row

/// A virtual best-of playlist. No context menu: there is nothing on the server to rename, delete, pin or
/// download — the row exists only as a doorway into the derived track list.
private struct BestOfPlaylistRow: View {
    let bestOf: ArtistBestOf

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtView(id: bestOf.coverArtId ?? bestOf.artistId, size: 112)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("The best of \(bestOf.artistName)")
                    .font(.cassetteCellTitle)
                    .lineLimit(1)
                Text("\(bestOf.songs.count) tracks")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
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
            .miniPlayerBottomMargin()
        }
    }
}

private struct OfflinePlaylistRow: View {
    let playlist: DownloadedPlaylist

    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            PlaylistCoverThumbnail(playlistId: playlist.playlistId, serverId: nil, coverArtId: playlist.coverArtId ?? playlist.playlistId, title: playlist.name, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.cassetteCellTitle)
                    .lineLimit(1)
                Text("\(playlist.tracksCount) tracks")
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
