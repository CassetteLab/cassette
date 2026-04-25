// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic

struct ArtistListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistListViewModel?

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
        .navigationTitle("Browse")
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = ArtistListViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: ArtistListViewModel) -> some View {
        if vm.isLoading && vm.indexes.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if container?.serverState.isOnline == false && vm.indexes.isEmpty {
            if let serverId = container?.serverState.activeServer?.id {
                OfflineBrowseContent(serverId: serverId)
            } else {
                EmptyStateView(
                    systemImage: "wifi.slash",
                    title: "You're Offline",
                    subtitle: "Connect to your server to browse artists."
                )
            }
        } else if let error = vm.error, vm.indexes.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Artists",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.indexes.isEmpty {
            EmptyStateView(
                systemImage: "music.mic",
                title: "No Artists",
                subtitle: "Your library appears to be empty."
            )
        } else {
            List(vm.indexes, id: \.name) { index in
                Section(index.name) {
                    ForEach(index.artist) { artist in
                        NavigationLink(value: artist) {
                            ArtistRow(artist: artist)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
            .navigationDestination(for: ArtistID3.self) { artist in
                ArtistDetailView(artist: artist)
            }
        }
    }
}

// MARK: - Offline Browse

private struct OfflineBrowseContent: View {
    let serverId: UUID
    @Query private var albums: [DownloadedAlbum]

    init(serverId: UUID) {
        self.serverId = serverId
        let sid = serverId
        _albums = Query(
            filter: #Predicate<DownloadedAlbum> { album in album.serverId == sid },
            sort: [SortDescriptor(\DownloadedAlbum.name)]
        )
    }

    var body: some View {
        if albums.isEmpty {
            EmptyStateView(
                systemImage: "wifi.slash",
                title: "You're Offline",
                subtitle: "No downloaded albums available. Download albums while online to listen offline."
            )
        } else {
            List {
                Section("Downloaded Albums") {
                    ForEach(albums) { album in
                        HStack(spacing: CassetteSpacing.m) {
                            CoverArtCard(id: album.coverArtId ?? album.albumId, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name)
                                    .font(.cassetteCellTitle)
                                    .lineLimit(1)
                                if let artist = album.artist {
                                    Text(artist)
                                        .font(.cassetteCaption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Text("\(album.tracksCount) track\(album.tracksCount == 1 ? "" : "s")")
                                .font(.cassetteCaption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, CassetteSpacing.xs)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
