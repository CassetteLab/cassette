// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic

struct AlbumsListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: AlbumListViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Albums")
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = AlbumListViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: AlbumListViewModel) -> some View {
        if vm.isLoading && vm.albums.isEmpty {
            LoadingStateView()
        } else if container?.serverState.isOnline == false && vm.albums.isEmpty {
            if let serverId = container?.serverState.activeServer?.id {
                OfflineAlbumsContent(serverId: serverId)
            } else {
                EmptyStateView(
                    systemImage: "wifi.slash",
                    title: "You're Offline",
                    subtitle: "Connect to your server to browse albums."
                )
            }
        } else if let error = vm.error, vm.albums.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Albums",
                subtitle: error.displayMessage,
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.albums.isEmpty {
            EmptyStateView(
                systemImage: "square.stack",
                title: "No Albums",
                subtitle: "Your library appears to be empty."
            )
        } else {
            #if os(macOS)
            albumsListMacOS(vm)
            #else
            ScrollViewReader { proxy in
                List(vm.albums) { album in
                    NavigationLink(destination: { AlbumDetailView(album: album) }) {
                        AlbumRow(
                            albumId: album.id,
                            name: album.name,
                            artist: album.artist,
                            year: album.year,
                            coverArtId: album.coverArt
                        )
                        .padding(.trailing, vm.albums.count >= 20 ? 28 : 0)
                    }
                    .id(album.id)
                }
                .listStyle(.plain)
                .refreshable { await vm.load() }
                .overlay(alignment: .trailing) {
                    if vm.albums.count >= 20 {
                        AlphabetJumpBar(
                            availableLetters: vm.albums.availableAlphabetLetters(keyPath: \.name),
                            onLetterTap: { letter in
                                if let id = firstAlphabetItemID(forLetter: letter, in: vm.albums, keyPath: \.name) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo(id, anchor: .top)
                                    }
                                }
                            }
                        )
                        .padding(.trailing, 4)
                    }
                }
            }
            #endif
        }
    }

    #if os(macOS)
    // macOS uses ScrollView+LazyVStack instead of List so that ScrollViewReader.scrollTo()
    // targets a SwiftUI-native scroll container — NSTableView-backed List does not integrate
    // correctly with ScrollViewReader and causes scroll offsets to land on the wrong row.
    @ViewBuilder
    private func albumsListMacOS(_ vm: AlbumListViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.albums) { album in
                        NavigationLink(destination: {
                            AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                        }) {
                            AlbumRow(
                                albumId: album.id,
                                name: album.name,
                                artist: album.artist,
                                year: album.year,
                                coverArtId: album.coverArt
                            )
                            .padding(.horizontal, CassetteSpacing.s)
                            .padding(.trailing, 32)
                        }
                        .buttonStyle(.plain)
                        .id(album.id)

                        Divider()
                            .padding(.leading, 56 + CassetteSpacing.m + CassetteSpacing.s)
                    }
                }
            }
            .refreshable { await vm.load() }
            .overlay(alignment: .trailing) {
                if vm.albums.count >= 20 {
                    AlphabetJumpBar(
                        availableLetters: vm.albums.availableAlphabetLetters(keyPath: \.name),
                        onLetterTap: { letter in
                            if let id = firstAlphabetItemID(forLetter: letter, in: vm.albums, keyPath: \.name) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                            }
                        }
                    )
                    .padding(.trailing, 8)
                }
            }
        }
    }
    #endif
}

// MARK: - Offline Albums

private struct OfflineAlbumsContent: View {
    let serverId: UUID
    @Query private var albums: [DownloadedAlbum]
    @Query private var tracks: [DownloadedTrack]

    init(serverId: UUID) {
        self.serverId = serverId
        let sid = serverId
        _albums = Query(
            filter: #Predicate<DownloadedAlbum> { album in album.serverId == sid },
            sort: [SortDescriptor(\DownloadedAlbum.name)]
        )
        _tracks = Query(filter: #Predicate<DownloadedTrack> { track in track.serverId == sid })
    }

    private var displayAlbums: [DownloadedAlbumDisplay] {
        DownloadedAlbumMerger.merge(records: albums, tracks: tracks)
    }

    var body: some View {
        if displayAlbums.isEmpty {
            EmptyStateView(
                systemImage: "wifi.slash",
                title: "You're Offline",
                subtitle: "No downloaded albums available. Download albums while online to listen offline."
            )
        } else {
            List {
                Section("Downloaded Albums") {
                    ForEach(displayAlbums) { display in
                        NavigationLink(destination: {
                            #if os(macOS)
                            AlbumDetailMacOS(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId)
                            #else
                            AlbumDetailView(albumId: display.albumId, albumName: display.name, mode: display.hasFullDownloadIntent ? .full : .downloadedOnly)
                            #endif
                        }) {
                            AlbumRow(
                                albumId: display.albumId,
                                name: display.name,
                                artist: display.artist,
                                year: nil,
                                coverArtId: display.coverArtId
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
