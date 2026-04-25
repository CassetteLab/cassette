// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic

struct HomeView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PinnedItem.sortOrder) private var allPinnedItems: [PinnedItem]
    @Query(sort: \DownloadedAlbum.downloadedAt, order: .reverse) private var recentDownloadedAlbums: [DownloadedAlbum]
    @Query(sort: \DownloadedPlaylist.downloadedAt, order: .reverse) private var recentDownloadedPlaylists: [DownloadedPlaylist]
    @State private var viewModel: HomeViewModel?
    @State private var showEditPinned = false
    @State private var navigateToSettings = false
    // Local mutable copy for smooth drag-to-reorder; synced from @Query on count changes.
    @State private var localPinnedItems: [PinnedItem] = []
    @State private var dropTargetId: String?

    private let recentColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: CassetteSpacing.m)
    ]
    private let pinnedColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var isOnline: Bool { container?.serverState.isOnline == true }

    private var recentDownloadedItems: [DownloadedItem] {
        let albumItems = recentDownloadedAlbums.map {
            DownloadedItem(
                id: "album:\($0.albumId)",
                itemId: $0.albumId,
                type: .album,
                name: $0.name,
                subtitle: $0.artist ?? "",
                coverArtId: $0.coverArtId,
                downloadedAt: $0.downloadedAt
            )
        }
        let playlistItems = recentDownloadedPlaylists.map {
            DownloadedItem(
                id: "playlist:\($0.playlistId)",
                itemId: $0.playlistId,
                type: .playlist,
                name: $0.name,
                subtitle: "",
                coverArtId: $0.coverArtId,
                downloadedAt: $0.downloadedAt
            )
        }
        return (albumItems + playlistItems)
            .sorted { $0.downloadedAt > $1.downloadedAt }
            .prefix(24)
            .map { $0 }
    }

    private var visiblePinnedItems: [PinnedItem] {
        guard container?.serverState.isOnline != true else { return localPinnedItems }
        return localPinnedItems.filter { isAvailableOffline($0) }
    }

    private func isAvailableOffline(_ item: PinnedItem) -> Bool {
        let itemId = item.itemId
        switch PinnedItemType(rawValue: item.itemType) {
        case .album:
            let descriptor = FetchDescriptor<DownloadedAlbum>(
                predicate: #Predicate { $0.albumId == itemId }
            )
            return (try? modelContext.fetch(descriptor).first) != nil
        case .playlist:
            let descriptor = FetchDescriptor<DownloadedPlaylist>(
                predicate: #Predicate { $0.playlistId == itemId }
            )
            return (try? modelContext.fetch(descriptor).first) != nil
        case .none:
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CassetteSpacing.xl) {
                if !visiblePinnedItems.isEmpty {
                    pinnedSection
                }
                librarySection
                recentlySection
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.top, CassetteSpacing.m)
            .padding(.bottom, CassetteSpacing.xl)
        }
        .cassetteContentWidth()
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    if !allPinnedItems.isEmpty {
                        Button { showEditPinned = true } label: {
                            Label("Edit Pinned", systemImage: "pin")
                        }
                    }
                    Button { navigateToSettings = true } label: {
                        Label("Settings", systemImage: "gear")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditPinned) { EditPinnedView() }
        .navigationDestination(isPresented: $navigateToSettings) { SettingsView() }
        .onAppear { localPinnedItems = allPinnedItems }
        .onChange(of: allPinnedItems.count) { _, _ in localPinnedItems = allPinnedItems }
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = HomeViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
    }

    // MARK: - Pinned section

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Pinned")
                .font(.cassetteSectionTitle)
            LazyVGrid(columns: pinnedColumns, spacing: CassetteSpacing.m) {
                ForEach(visiblePinnedItems) { item in
                    HomePinnedCard(item: item)
                        .scaleEffect(dropTargetId == item.id ? 1.05 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: dropTargetId)
                        .draggable(item.id)
                        .dropDestination(for: String.self) { droppedIds, _ in
                            guard let sourceId = droppedIds.first,
                                  sourceId != item.id,
                                  let sourceIdx = localPinnedItems.firstIndex(where: { $0.id == sourceId }),
                                  let destIdx = localPinnedItems.firstIndex(where: { $0.id == item.id })
                            else { return false }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                localPinnedItems.move(
                                    fromOffsets: IndexSet(integer: sourceIdx),
                                    toOffset: destIdx > sourceIdx ? destIdx + 1 : destIdx
                                )
                            }
                            container?.pinService.reorder(items: localPinnedItems)
                            return true
                        } isTargeted: { targeted in
                            dropTargetId = targeted ? item.id : nil
                        }
                }
            }
        }
    }

    // MARK: - Library section

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Library")
                .font(.cassetteSectionTitle)
            VStack(spacing: 0) {
                HomeLibraryRow(title: "Playlists", systemImage: "music.note.list") {
                    PlaylistListView()
                }
                Divider().padding(.leading, 52)
                HomeLibraryRow(title: "Albums", systemImage: "square.stack") {
                    AlbumsListView()
                }
                Divider().padding(.leading, 52)
                HomeLibraryRow(title: "Artists", systemImage: "music.mic") {
                    ArtistListView()
                }
                Divider().padding(.leading, 52)
                HomeLibraryRow(title: "Favorites", systemImage: "heart.fill") {
                    FavoritesView()
                }
                Divider().padding(.leading, 52)
                HomeLibraryRow(title: "Downloads", systemImage: "arrow.down.circle.fill") {
                    DownloadedView()
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CassetteCornerRadius.standard))
        }
    }

    // MARK: - Recently section (online = Recently Added, offline = Recently Downloaded)

    @ViewBuilder
    private var recentlySection: some View {
        if isOnline {
            if let vm = viewModel, !vm.recentAlbums.isEmpty || vm.isLoading {
                VStack(alignment: .leading, spacing: CassetteSpacing.s) {
                    Text("Recently Added")
                        .font(.cassetteSectionTitle)
                    if vm.isLoading && vm.recentAlbums.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, CassetteSpacing.l)
                    } else {
                        LazyVGrid(columns: recentColumns, spacing: CassetteSpacing.m) {
                            ForEach(vm.recentAlbums) { album in
                                NavigationLink(destination: AlbumDetailView(album: album)) {
                                    HomeAlbumCell(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: CassetteSpacing.s) {
                Text("Recently Downloaded")
                    .font(.cassetteSectionTitle)
                if recentDownloadedItems.isEmpty {
                    EmptyStateView(
                        systemImage: "arrow.down.circle",
                        title: "No downloads yet",
                        subtitle: "Albums and playlists you download will appear here"
                    )
                } else {
                    LazyVGrid(columns: recentColumns, spacing: CassetteSpacing.m) {
                        ForEach(recentDownloadedItems) { item in
                            HomeDownloadedItemCard(item: item)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - HomePinnedCard

private struct HomePinnedCard: View {
    let item: PinnedItem

    @ViewBuilder
    private var destination: some View {
        switch PinnedItemType(rawValue: item.itemType) {
        case .album:
            AlbumDetailView(albumId: item.itemId, albumName: item.displayName)
        case .playlist:
            PlaylistDetailView(playlistId: item.itemId, name: item.displayName)
        case .none:
            EmptyView()
        }
    }

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                GeometryReader { geo in
                    CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(geo.size.width * 2))
                        .frame(width: geo.size.width, height: geo.size.width)
                        .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
                }
                .aspectRatio(1, contentMode: .fit)
                Text(item.displayName)
                    .font(.cassetteCaption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !item.displaySubtitle.isEmpty {
                    Text(item.displaySubtitle)
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .collectionContextMenu(
            itemType: PinnedItemType(rawValue: item.itemType) ?? .album,
            itemId: item.itemId,
            displayName: item.displayName,
            displaySubtitle: item.displaySubtitle,
            coverArtId: item.coverArtId,
            favoriteType: item.itemType == PinnedItemType.album.rawValue ? .album : nil
        )
    }
}

// MARK: - HomeLibraryRow

private struct HomeLibraryRow<Destination: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: CassetteSpacing.m) {
                Image(systemName: systemImage)
                    .frame(width: 28)
                    .foregroundStyle(Color.cassetteAccent)
                Text(title)
                    .font(.cassetteCellTitle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, CassetteSpacing.m)
            .padding(.vertical, CassetteSpacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(LibraryRowButtonStyle())
    }
}

private struct LibraryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
    }
}

// MARK: - HomeDownloadedItemCard

private struct HomeDownloadedItemCard: View {
    let item: DownloadedItem
    @Environment(\.modelContext) private var modelContext

    @ViewBuilder
    private var destination: some View {
        switch item.type {
        case .album:
            AlbumDetailView(albumId: item.itemId, albumName: item.name)
        case .playlist:
            PlaylistDetailView(playlistId: item.itemId, name: item.name)
        }
    }

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                GeometryReader { geo in
                    CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(geo.size.width * 2))
                        .frame(width: geo.size.width, height: geo.size.width)
                        .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
                }
                .aspectRatio(1, contentMode: .fit)
                Text(item.name)
                    .font(.cassetteCaption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .lazyCollectionContextMenu(
            itemType: item.type == .album ? .album : .playlist,
            itemId: item.itemId,
            displayName: item.name,
            displaySubtitle: item.subtitle,
            coverArtId: item.coverArtId,
            favoriteType: item.type == .album ? .album : nil
        ) {
            switch item.type {
            case .album:
                let aid = item.itemId
                let tracks = (try? modelContext.fetch(
                    FetchDescriptor<DownloadedTrack>(
                        predicate: #Predicate { $0.albumId == aid }
                    )
                )) ?? []
                return tracks
                    .sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
                    .map { DisplayableSong(from: $0) }
            case .playlist:
                let pid = item.itemId
                let playlists = (try? modelContext.fetch(
                    FetchDescriptor<DownloadedPlaylist>(
                        predicate: #Predicate { $0.playlistId == pid }
                    )
                )) ?? []
                let songIds = playlists.first?.songIds ?? []
                let allTracks = (try? modelContext.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
                let trackBySongId = Dictionary(
                    allTracks.map { ($0.songId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                return songIds.compactMap { trackBySongId[$0] }.map { DisplayableSong(from: $0) }
            }
        }
    }
}

// MARK: - DownloadedItem

private nonisolated struct DownloadedItem: Identifiable, Sendable {
    nonisolated enum ItemType: Sendable {
        case album
        case playlist
    }
    let id: String
    let itemId: String
    let type: ItemType
    let name: String
    let subtitle: String
    let coverArtId: String?
    let downloadedAt: Date
}

// MARK: - HomeAlbumCell

private struct HomeAlbumCell: View {
    let album: AlbumID3

    @Environment(\.appContainer) private var container

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            GeometryReader { geo in
                CoverArtView(id: album.coverArt ?? album.id, size: Int(geo.size.width * 2))
                    .frame(width: geo.size.width, height: geo.size.width)
                    .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(album.name)
                .font(.cassetteCaption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let artist = album.artist {
                Text(artist)
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .lazyCollectionContextMenu(
            itemType: .album,
            itemId: album.id,
            displayName: album.name,
            displaySubtitle: album.artist ?? "",
            coverArtId: album.coverArt,
            favoriteType: .album
        ) {
            let detail = try await container?.libraryService.album(id: album.id)
            return (detail?.song ?? []).map { DisplayableSong(from: $0) }
        }
    }
}
