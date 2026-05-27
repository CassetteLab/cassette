// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import SwiftData
import SwiftSonic

struct RootViewMacOS: View {
    @Environment(\.appContainer) private var container
    @Query(sort: \PinnedItem.sortOrder) private var pinnedItems: [PinnedItem]
    @State private var selection: SidebarDestination? = .section(.home)
    @State private var searchQuery: String = ""
    @State private var isShowingFullPlayer = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var navigationPath = NavigationPath()

    var body: some View {
        ZStack {
            MainWindowConfigurator(isFullPlayerVisible: isShowingFullPlayer)
                .frame(width: 0, height: 0)

            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarContent
            } detail: {
                detailContent
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 120)
                    }
            }
            .navigationSplitViewStyle(.balanced)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.6), location: 0.5),
                        .init(color: Color(nsColor: .windowBackgroundColor), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                BottomPlayerBar(onArtworkTap: { withAnimation { isShowingFullPlayer = true } })
                    .frame(maxWidth: 600)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            .searchable(text: $searchQuery, placement: .sidebar)

            if isShowingFullPlayer {
                FullPlayerExpandedView(isPresented: $isShowingFullPlayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .zIndex(1)
                    .toolbar(.hidden, for: .windowToolbar)
            }
        }
        .frame(minWidth: 1100, minHeight: 500)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: selection) { _, _ in
            if isShowingFullPlayer { withAnimation { isShowingFullPlayer = false } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteTogglePlayPause)) { _ in
            Task { await handleTogglePlayPause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteSkipNext)) { _ in
            Task { try? await container?.playerService.skipToNext() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteSkipPrevious)) { _ in
            Task { try? await container?.playerService.skipToPrevious() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteToggleShuffle)) { _ in
            Task { await container?.playerService.toggleShuffle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteToggleRepeat)) { _ in
            Task {
                guard let container else { return }
                await container.playerService.setRepeatMode(container.playerState.repeatMode.next)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteOpenFullPlayer)) { _ in
            withAnimation { isShowingFullPlayer = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteOpenFullPlayerLyrics)) { _ in
            withAnimation { isShowingFullPlayer = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteSelectAlbums)) { _ in
            selection = .section(.albums)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteNavigateToAlbum)) { note in
            guard let id   = note.userInfo?["albumId"]   as? String,
                  let name = note.userInfo?["albumName"]  as? String else { return }
            let coverArtId = note.userInfo?["coverArtId"] as? String
            withAnimation { isShowingFullPlayer = false }
            selection = .section(.home)
            navigationPath.append(HomeDestination.albumById(id: id, name: name, subtitle: "", coverArtId: coverArtId))
        }
        .onReceive(NotificationCenter.default.publisher(for: .cassetteNavigateToArtist)) { note in
            guard let id   = note.userInfo?["artistId"]   as? String,
                  let name = note.userInfo?["artistName"]  as? String else { return }
            let coverArtId = note.userInfo?["coverArtId"] as? String
            withAnimation { isShowingFullPlayer = false }
            selection = .section(.home)
            navigationPath.append(HomeDestination.artistById(id: id, name: name, coverArtId: coverArtId))
        }
    }

    // MARK: - Playback

    private func handleTogglePlayPause() async {
        guard let container else { return }
        if container.playerState.playbackState == .playing {
            await container.playerService.pause()
        } else {
            await container.playerService.resume()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selection) {
            Section {
                sidebarRow(.home)
                sidebarRow(.radio)
                sidebarRow(.freshReleases)
                sidebarRow(.wrapped)
            }

            Section("Library") {
                sidebarRow(.albums)
                sidebarRow(.artists)
                sidebarRow(.playlists)
                sidebarRow(.favorites)
                sidebarRow(.downloads)
            }

            if !pinnedItems.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedItems) { item in
                        pinnedRow(item)
                            .tag(SidebarDestination.pinned(item.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            userFooter
        }
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        Label(section.displayLabel, systemImage: section.systemImage)
            .tag(SidebarDestination.section(section))
    }

    @ViewBuilder
    private func pinnedRow(_ item: PinnedItem) -> some View {
        Label {
            Text(item.displayName)
        } icon: {
            if let coverArtId = item.coverArtId {
                CoverArtView(
                    id: coverArtId,
                    size: 22,
                    cornerRadius: 3,
                    placeholderSystemImage: item.itemType == PinnedItemType.album.rawValue
                        ? "square.stack" : "music.note.list"
                )
                .frame(width: 22, height: 22)
            } else {
                Image(systemName: item.itemType == PinnedItemType.album.rawValue
                    ? "square.stack" : "music.note.list"
                )
            }
        }
        .contextMenu {
            Button {
                selection = .pinned(item.id)
            } label: {
                Label("Open", systemImage: "arrow.up.right")
            }

            Divider()

            Button(role: .destructive) {
                if let type = PinnedItemType(rawValue: item.itemType) {
                    container?.pinService.unpin(itemType: type, itemId: item.itemId)
                }
            } label: {
                Label("Unpin", systemImage: "pin.slash")
            }
        }
    }

    @ViewBuilder
    private var userFooter: some View {
        if let server = container?.serverState.activeServer {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(server.displayName)
                            .font(.callout)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(server.username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !searchQuery.isEmpty {
                    SearchView(searchQuery: $searchQuery, path: $navigationPath)
                } else {
                    detailView(for: selection ?? .section(.home))
                }
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .album(let album):
                    AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                case .artist(let artist):
                    ArtistDetailMacOS(artistId: artist.id, artistName: artist.name, coverArtId: artist.coverArt)
                case .playlist(let playlist):
                    PlaylistDetailMacOS(playlistId: playlist.id, name: playlist.name, coverArtId: playlist.coverArt)
                case .downloadedAlbum(let display):
                    AlbumDetailMacOS(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId)
                case .albumById(let id, let name, _, let coverArtId):
                    AlbumDetailMacOS(albumId: id, albumName: name, coverArtId: coverArtId)
                case .playlistById(let id, let name, let coverArtId):
                    PlaylistDetailMacOS(playlistId: id, name: name, coverArtId: coverArtId)
                case .offlineAlbum(let album):
                    AlbumDetailMacOS(albumId: album.albumId, albumName: album.albumName, coverArtId: album.coverArtId)
                case .offlineArtist(let artist):
                    OfflineArtistAlbumsView(artist: artist)
                case .artistById(let id, let name, let coverArtId):
                    ArtistDetailMacOS(artistId: id, artistName: name, coverArtId: coverArtId)
                default:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func detailView(for destination: SidebarDestination) -> some View {
        switch destination {
        case .section(let section):
            sectionView(for: section)
        case .pinned(let id):
            pinnedDetail(for: id)
                .id(id)
        }
    }

    @ViewBuilder
    private func sectionView(for section: SidebarSection) -> some View {
        switch section {
        case .home:          HomeView()
        case .radio:         RadioListView()
        case .freshReleases: FreshReleasesSidebarView()
        case .wrapped:       WrappedView()
        case .albums:    AlbumsListView()
        case .artists:   ArtistsListMacOS()
        case .playlists: PlaylistListView()
        case .favorites: FavoritesView()
        case .downloads: DownloadedView()
        }
    }

    @ViewBuilder
    private func pinnedDetail(for id: String) -> some View {
        if let item = pinnedItems.first(where: { $0.id == id }) {
            switch PinnedItemType(rawValue: item.itemType) {
            case .album:
                AlbumDetailMacOS(
                    albumId: item.itemId,
                    albumName: item.displayName,
                    coverArtId: item.coverArtId,
                    showBackButton: false
                )
            case .playlist:
                PlaylistDetailMacOS(
                    playlistId: item.itemId,
                    name: item.displayName,
                    coverArtId: item.coverArtId,
                    showBackButton: false
                )
            case .none:
                ContentUnavailableView("Unknown item type", systemImage: "questionmark")
            }
        } else {
            ContentUnavailableView("Item not found", systemImage: "pin.slash")
        }
    }
}

// MARK: - Fresh Releases sidebar wrapper

private struct FreshReleasesSidebarView: View {
    @Environment(\.appContainer) private var container
    @State private var vm: AllFreshReleasesViewModel?

    var body: some View {
        Group {
            if let vm {
                AllFreshReleasesView(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: container?.serverState.activeServer?.id) {
            guard let container else { return }
            if vm == nil {
                vm = AllFreshReleasesViewModel(recommendationService: container.recommendationService)
            }
            await vm?.loadReleases()
        }
    }
}

// MARK: - Window configurator

private struct MainWindowConfigurator: NSViewRepresentable {
    let isFullPlayerVisible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.setFrameAutosaveName("CassetteMainWindow")
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titlebarAppearsTransparent = isFullPlayerVisible
            window.isMovableByWindowBackground = isFullPlayerVisible
        }
    }
}
#endif
