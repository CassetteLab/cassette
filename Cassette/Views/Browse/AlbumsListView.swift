// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic
import OSLog

struct AlbumsListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: AlbumListViewModel?
    /// Shared album ordering, persisted and reused by the artist discography too.
    @AppStorage("cassette.albumSort") private var albumSort: AlbumSort = .recentlyAdded
    /// List vs grid layout. Defaults preserve each platform's current look (macOS grid, iOS list).
    #if os(macOS)
    @AppStorage("cassette.albumListGrid") private var gridLayout = true
    #else
    @AppStorage("cassette.albumListGrid") private var gridLayout = false
    #endif

    /// Albums in the user's chosen order (client-side, so switching sort never re-fetches).
    private func sortedAlbums(_ vm: AlbumListViewModel) -> [AlbumID3] { albumSort.sorted(vm.albums) }

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        #if os(iOS)
        .cassetteContentWidth()
        #endif
        .navigationTitle("Albums")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    AlbumSortMenu(sort: $albumSort)
                    Button {
                        gridLayout.toggle()
                    } label: {
                        Image(systemName: gridLayout ? "list.bullet" : "square.grid.2x2")
                    }
                    .accessibilityLabel(gridLayout ? "List view" : "Grid view")
                }
            }
        }
        .task(id: container?.serverState.isOnline) {
            Logger.boot.notice("🟢 AlbumsListView task fired — activeServer=\(String(describing: container?.serverState.activeServer?.baseURL), privacy: .public) isOnline=\(String(describing: container?.serverState.isOnline), privacy: .public)")
            guard let svc = container?.libraryService else {
                Logger.boot.error("🔴 AlbumsListView: container?.libraryService is nil — skipping")
                return
            }
            if viewModel == nil { viewModel = AlbumListViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else {
                Logger.boot.notice("🟡 AlbumsListView: isOnline=false — skipping load")
                return
            }
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
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.albums.isEmpty {
            EmptyStateView(
                systemImage: "square.stack",
                title: "No Albums",
                subtitle: "Your library appears to be empty."
            )
        } else if gridLayout {
            albumsGrid(vm)
        } else {
            albumsList(vm)
        }
    }

    /// List of AlbumRow (with the A–Z jump bar on iOS when sorted by name).
    @ViewBuilder
    private func albumsList(_ vm: AlbumListViewModel) -> some View {
        let albums = sortedAlbums(vm)
        ScrollViewReader { proxy in
            List(albums) { album in
                NavigationLink(value: HomeDestination.album(album)) {
                    AlbumRow(
                        albumId: album.id,
                        name: album.name,
                        artist: album.artist,
                        year: album.year,
                        coverArtId: album.coverArt
                    )
                }
                .id(album.id)
            }
            .listStyle(.plain)
            .miniPlayerBottomMargin()
            .refreshable { await vm.load() }
            #if os(iOS)
            .safeAreaInset(edge: .trailing, spacing: 0) {
                // The A–Z jump bar only makes sense when sorted by name.
                if albumSort == .name && albums.count >= 20 {
                    AlphabetJumpBar(
                        availableLetters: albums.availableAlphabetLetters(keyPath: \.name),
                        onLetterTap: { letter in
                            if let id = firstAlphabetItemID(forLetter: letter, in: albums, keyPath: \.name) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                            }
                        }
                    )
                    .padding(.trailing, 4)
                }
            }
            #endif
        }
    }

    /// Grid of AlbumGridCell — responsive column count on macOS, adaptive on iOS.
    @ViewBuilder
    private func albumsGrid(_ vm: AlbumListViewModel) -> some View {
        #if os(macOS)
        GeometryReader { geo in
            let count = Self.gridColumnCount(for: geo.size.width)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(sortedAlbums(vm)) { album in
                        NavigationLink(value: HomeDestination.album(album)) {
                            AlbumGridCell(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .refreshable { await vm.load() }
        }
        #else
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: CassetteSpacing.l)], spacing: CassetteSpacing.l) {
                ForEach(sortedAlbums(vm)) { album in
                    NavigationLink(value: HomeDestination.album(album)) {
                        AlbumGridCell(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(CassetteSpacing.l)
        }
        .refreshable { await vm.load() }
        .miniPlayerBottomMargin()
        #endif
    }

    #if os(macOS)
    private static func gridColumnCount(for width: CGFloat) -> Int {
        switch width {
        case ..<900:  return 3
        case ..<1200: return 4
        case ..<1600: return 5
        default:      return 6
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
                        NavigationLink(value: HomeDestination.downloadedAlbum(display)) {
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
