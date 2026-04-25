// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic

struct PlaylistListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: PlaylistListViewModel?
    @State private var showPinLimitAlert = false

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Playlists")
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                subtitle: error.localizedDescription,
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
                NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                    HStack(spacing: CassetteSpacing.m) {
                        CoverArtCard(id: playlist.coverArt ?? playlist.id, size: 56)
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
                }
                .contextMenu {
                    if container?.pinService.isPinned(itemType: .playlist, itemId: playlist.id) == true {
                        Button {
                            container?.pinService.unpin(itemType: .playlist, itemId: playlist.id)
                        } label: {
                            Label("Unpin from Home", systemImage: "pin.slash")
                        }
                    } else {
                        Button {
                            guard let serverId = container?.serverState.activeServer?.id,
                                  let pin = container?.pinService else { return }
                            do {
                                try pin.pin(itemType: .playlist, itemId: playlist.id,
                                            displayName: playlist.name, displaySubtitle: "Playlist",
                                            coverArtId: playlist.coverArt, serverId: serverId)
                            } catch PinError.limitReached {
                                showPinLimitAlert = true
                            } catch {}
                        } label: {
                            Label("Pin to Home", systemImage: "pin")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
            .alert("Pin Limit Reached", isPresented: $showPinLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(PinError.limitReached.errorDescription ?? "")
            }
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
                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
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
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
