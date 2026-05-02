// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

#if os(macOS)
import SwiftUI
import SwiftData

struct RootViewMacOS: View {
    @Environment(\.appContainer) private var container
    @Query(sort: \PinnedItem.sortOrder) private var pinnedItems: [PinnedItem]
    @State private var selection: SidebarDestination? = .section(.home)
    @State private var searchQuery: String = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var isShowingFullPlayer = false

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            ZStack(alignment: .bottom) {
                Group {
                    if isShowingFullPlayer {
                        FullPlayerExpandedView(isPresented: $isShowingFullPlayer)
                    } else {
                        detailContent
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !isShowingFullPlayer {
                        Color.clear.frame(height: 120)
                    }
                }

                if !isShowingFullPlayer {
                    BottomPlayerBar(onArtworkTap: { withAnimation { isShowingFullPlayer = true } })
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .zIndex(1)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1100, minHeight: 500)
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
        .onReceive(NotificationCenter.default.publisher(for: .cassetteFocusSearch)) { _ in
            searchFieldFocused = true
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
        .safeAreaInset(edge: .top, spacing: 0) {
            searchField
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            userFooter
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            TextField("Search your library", text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.bar)
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
        NavigationStack {
            if !searchQuery.isEmpty {
                SearchView(searchQuery: $searchQuery)
            } else {
                detailView(for: selection ?? .section(.home))
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
        }
    }

    @ViewBuilder
    private func sectionView(for section: SidebarSection) -> some View {
        switch section {
        case .home:      HomeView()
        case .radio:     RadioListView()
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
#endif
