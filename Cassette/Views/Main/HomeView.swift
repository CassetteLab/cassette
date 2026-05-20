// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic

struct HomeView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PinnedItem.sortOrder) private var allPinnedItems: [PinnedItem]
    @Query private var recentDownloadedAlbums: [DownloadedAlbum]
    @Query private var recentDownloadedPlaylists: [DownloadedPlaylist]
    init() {
        var albumDescriptor = FetchDescriptor<DownloadedAlbum>(
            sortBy: [SortDescriptor(\DownloadedAlbum.downloadedAt, order: .reverse)]
        )
        albumDescriptor.fetchLimit = 24
        _recentDownloadedAlbums = Query(albumDescriptor)

        var playlistDescriptor = FetchDescriptor<DownloadedPlaylist>(
            sortBy: [SortDescriptor(\DownloadedPlaylist.downloadedAt, order: .reverse)]
        )
        playlistDescriptor.fetchLimit = 24
        _recentDownloadedPlaylists = Query(playlistDescriptor)
    }

    @Namespace private var pinnedZoomNamespace
    @Namespace private var recentlyAddedZoomNamespace
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @State private var viewModel: HomeViewModel?
    @State private var showEditPinned = false
    @State private var navigateToSettings = false
    @State private var navigateToAllAlbums = false
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
                #if os(iOS)
                if !visiblePinnedItems.isEmpty {
                    pinnedSection
                }
                #endif
                #if os(iOS)
                librarySection
                #endif
                #if os(macOS)
                macOSCarousels
                #else
                recentlySection
                #endif
            }
            .padding(.horizontal, CassetteSpacing.l)
            .padding(.top, CassetteSpacing.m)
            .padding(.bottom, CassetteSpacing.xl)
        }
        .cassetteContentWidth()
        .navigationTitle("Home")
        .toolbar {
            #if !os(macOS)
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
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            #endif
        }
        .sheet(isPresented: $showEditPinned) { EditPinnedView() }
        .navigationDestination(isPresented: $navigateToSettings) { SettingsView() }
        #if os(macOS)
        .navigationDestination(isPresented: $navigateToAllAlbums) { AlbumsListView() }
        #endif
        .navigationDestination(for: HomeDestination.self) { destination in
            switch destination {
            case .libraryAlbums:
                #if os(iOS)
                AlbumsListView()
                #else
                EmptyView()
                #endif
            case .libraryArtists:
                #if os(iOS)
                ArtistListView()
                #else
                EmptyView()
                #endif
            case .libraryPlaylists:
                #if os(iOS)
                PlaylistListView()
                #else
                EmptyView()
                #endif
            case .libraryFavorites:
                #if os(iOS)
                FavoritesView()
                #else
                EmptyView()
                #endif
            case .libraryDownloads:
                #if os(iOS)
                DownloadedView()
                #else
                EmptyView()
                #endif
            case .album(let album):
                #if os(macOS)
                AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                #else
                AlbumDetailView(
                    album: album,
                    zoomSourceId: album.id,
                    zoomNamespace: recentlyAddedZoomNamespace,
                    coverArtId: album.coverArt,
                    initialDominantColor: colorExtractor.dominantColor(for: album.coverArt ?? album.id, image: nil)
                )
                #endif
            case .artist(let artist):
                #if os(macOS)
                ArtistDetailMacOS(artistId: artist.id, artistName: artist.name, coverArtId: artist.coverArt)
                #else
                ArtistDetailView(artist: artist)
                #endif
            case .playlist(let playlist):
                #if os(macOS)
                PlaylistDetailMacOS(playlistId: playlist.id, name: playlist.name, coverArtId: playlist.coverArt)
                #else
                PlaylistDetailView(playlist: playlist)
                #endif
            case .downloadedAlbum(let display):
                #if os(macOS)
                AlbumDetailMacOS(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId)
                #else
                AlbumDetailView(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId, mode: .downloadedOnly)
                #endif
            case .albumById(let id, let name, _, let coverArtId):
                #if os(macOS)
                AlbumDetailMacOS(albumId: id, albumName: name, coverArtId: coverArtId)
                #else
                AlbumDetailView(albumId: id, albumName: name, coverArtId: coverArtId)
                #endif
            case .playlistById(let id, let name, let coverArtId):
                #if os(macOS)
                PlaylistDetailMacOS(playlistId: id, name: name, coverArtId: coverArtId)
                #else
                PlaylistDetailView(playlistId: id, name: name, coverArtId: coverArtId)
                #endif
            case .offlineArtist(let artist):
                OfflineArtistAlbumsView(artist: artist)
            case .offlineAlbum(let album):
                #if os(macOS)
                AlbumDetailMacOS(albumId: album.albumId, albumName: album.albumName, coverArtId: album.coverArtId)
                #else
                AlbumDetailView(albumId: album.albumId, albumName: album.albumName, coverArtId: album.coverArtId)
                #endif
            }
        }
        .onAppear { localPinnedItems = allPinnedItems }
        .onChange(of: allPinnedItems.count) { _, _ in localPinnedItems = allPinnedItems }
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = HomeViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
    }

    // MARK: - macOS carousels

    #if os(macOS)
    @ViewBuilder
    private var macOSCarousels: some View {
        VStack(alignment: .leading, spacing: 32) {
            if isOnline {
                smartShuffleCard
            }
            if let vm = viewModel {
                if vm.isLoading && vm.recentAlbums.isEmpty && vm.recentlyPlayed.isEmpty && vm.mostPlayed.isEmpty {
                    ProgressView("Loading your library...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let error = vm.error, vm.recentAlbums.isEmpty {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load",
                        subtitle: error.displayMessage,
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                } else if !vm.isLoading && vm.recentAlbums.isEmpty && vm.recentlyPlayed.isEmpty && vm.mostPlayed.isEmpty {
                    EmptyStateView(
                        systemImage: "music.note.list",
                        title: "No music yet",
                        subtitle: "Add some music to your server to get started"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 32) {
                        if !vm.recentAlbums.isEmpty {
                            CarouselSection(title: "Recently Added", onSeeAll: { navigateToAllAlbums = true }) {
                                ForEach(vm.recentAlbums) { album in
                                    CarouselAlbumCard(album: album)
                                }
                            }
                        }
                        if !vm.recentlyPlayed.isEmpty {
                            CarouselSection(title: "Recently Played") {
                                ForEach(vm.recentlyPlayed) { album in
                                    CarouselAlbumCard(album: album)
                                }
                            }
                        }
                        if !vm.mostPlayed.isEmpty {
                            CarouselSection(title: "Most Played") {
                                ForEach(vm.mostPlayed) { album in
                                    CarouselAlbumCard(album: album)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var smartShuffleCard: some View {
        Button {
            Task {
                guard let container else { return }
                do {
                    try await container.playerService.playSmartShuffle()
                } catch {
                    let msg: String
                    if case CassetteError.smartShuffleEmpty = error {
                        msg = "Smart Shuffle unavailable — try playing some tracks first or download more music for offline use."
                    } else {
                        msg = "Smart Shuffle failed. Please try again."
                    }
                    container.toastService.showError(msg)
                }
            }
        } label: {
            HStack(spacing: CassetteSpacing.s) {
                Image(systemName: "shuffle.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.cassetteAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Shuffle")
                        .font(.cassetteCellTitle)
                    Text("Rediscover your library — tracks you haven't heard recently")
                        .font(.cassetteCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.cassetteAccent)
            }
            .padding(CassetteSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cassetteAccent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Pinned section

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text("Pinned")
                .font(.cassetteSectionTitle)
            LazyVGrid(columns: pinnedColumns, spacing: CassetteSpacing.m) {
                ForEach(visiblePinnedItems) { item in
                    HomePinnedCard(item: item, namespace: pinnedZoomNamespace)
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
                NavigationLink(value: HomeDestination.libraryPlaylists) {
                    HomeLibraryRowLabel(title: "Playlists", systemImage: "music.note.list")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                NavigationLink(value: HomeDestination.libraryAlbums) {
                    HomeLibraryRowLabel(title: "Albums", systemImage: "square.stack")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                NavigationLink(value: HomeDestination.libraryArtists) {
                    HomeLibraryRowLabel(title: "Artists", systemImage: "music.mic")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                NavigationLink(value: HomeDestination.libraryFavorites) {
                    HomeLibraryRowLabel(title: "Favorites", systemImage: "heart.fill")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                NavigationLink(value: HomeDestination.libraryDownloads) {
                    HomeLibraryRowLabel(title: "Downloads", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.plain)
            }
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
                        LazyVGrid(columns: recentColumns, spacing: CassetteSpacing.m) {
                            ForEach(0..<6, id: \.self) { _ in SkeletonAlbumCard() }
                        }
                    } else {
                        LazyVGrid(columns: recentColumns, spacing: CassetteSpacing.m) {
                            ForEach(vm.recentAlbums) { album in
                                NavigationLink(value: HomeDestination.album(album)) {
                                    HomeAlbumCell(album: album, namespace: recentlyAddedZoomNamespace)
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
                            let dest: HomeDestination = item.type == .album
                                ? .albumById(id: item.itemId, name: item.name, subtitle: item.subtitle, coverArtId: item.coverArtId)
                                : .playlistById(id: item.itemId, name: item.name, coverArtId: item.coverArtId)
                            HomeDownloadedItemCard(item: item, destination: dest)
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
    let namespace: Namespace.ID
    @Environment(\.appContainer) private var container
    @Environment(\.modelContext) private var modelContext
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @State private var coverImage: PlatformImage?
    @AppStorage("coverArtUploadVersion") private var coverArtUploadVersion = 0

    private var homeNavDestination: HomeDestination {
        switch PinnedItemType(rawValue: item.itemType) {
        case .album:
            .albumById(id: item.itemId, name: item.displayName, subtitle: item.displaySubtitle, coverArtId: item.coverArtId)
        case .playlist:
            .playlistById(id: item.itemId, name: item.displayName, coverArtId: item.coverArtId)
        case .none:
            .albumById(id: item.itemId, name: item.displayName, subtitle: item.displaySubtitle, coverArtId: item.coverArtId)
        }
    }

    var body: some View {
        NavigationLink(value: homeNavDestination) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                GeometryReader { geo in
                    CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(geo.size.width * 2))
                        .frame(width: geo.size.width, height: geo.size.width)
                        .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
                        .id("\(item.coverArtId ?? item.itemId)_\(coverArtUploadVersion)")
                }
                .aspectRatio(1, contentMode: .fit)
                .modifier(ConditionalMatchedTransitionSource(id: item.id, namespace: namespace))
                Text(item.displayName)
                    .font(.cassetteCaption)
                    .fontWeight(.semibold)
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
        .onAppear {
            Task { coverImage = await artworkImageCache.load(coverArtId: item.coverArtId ?? item.itemId) }
        }
        .lazyCollectionContextMenu(
            itemType: PinnedItemType(rawValue: item.itemType) ?? .album,
            itemId: item.itemId,
            displayName: item.displayName,
            displaySubtitle: item.displaySubtitle,
            coverArtId: item.coverArtId,
            coverImage: coverImage,
            favoriteType: item.itemType == PinnedItemType.album.rawValue ? .album : nil
        ) {
            let itemId = item.itemId
            switch PinnedItemType(rawValue: item.itemType) {
            case .album:
                if container?.serverState.isOnline == true,
                   let detail = try? await container?.libraryService.album(id: itemId) {
                    return detail.song?.map { DisplayableSong(from: $0) } ?? []
                }
                let tracks = (try? modelContext.fetch(
                    FetchDescriptor<DownloadedTrack>(
                        predicate: #Predicate { $0.albumId == itemId }
                    )
                )) ?? []
                return tracks
                    .sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
                    .map { DisplayableSong(from: $0) }
            case .playlist:
                if container?.serverState.isOnline == true,
                   let detail = try? await container?.libraryService.playlist(id: itemId) {
                    return (detail.entry ?? []).map { DisplayableSong(from: $0) }
                }
                let playlists = (try? modelContext.fetch(
                    FetchDescriptor<DownloadedPlaylist>(
                        predicate: #Predicate { $0.playlistId == itemId }
                    )
                )) ?? []
                let songIds = playlists.first?.songIds ?? []
                let allTracks = (try? modelContext.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
                let trackBySongId = Dictionary(
                    allTracks.map { ($0.songId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                return songIds.compactMap { trackBySongId[$0] }.map { DisplayableSong(from: $0) }
            case .none:
                return []
            }
        }
    }
}

// MARK: - HomeLibraryRowLabel

private struct HomeLibraryRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.cassetteAccent)
                    .frame(width: 30, height: 30)
                Image(systemName: systemImage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
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
}

// MARK: - HomeDownloadedItemCard

private struct HomeDownloadedItemCard: View {
    let item: DownloadedItem
    let destination: HomeDestination
    @Environment(\.modelContext) private var modelContext
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?
    @AppStorage("coverArtUploadVersion") private var coverArtUploadVersion = 0

    var body: some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                GeometryReader { geo in
                    CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(geo.size.width * 2))
                        .frame(width: geo.size.width, height: geo.size.width)
                        .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
                        .id("\(item.coverArtId ?? item.itemId)_\(coverArtUploadVersion)")
                }
                .aspectRatio(1, contentMode: .fit)
                Text(item.name)
                    .font(.cassetteCaption)
                    .fontWeight(.semibold)
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
        .onAppear {
            Task { coverImage = await artworkImageCache.load(coverArtId: item.coverArtId ?? item.itemId) }
        }
        .lazyCollectionContextMenu(
            itemType: item.type == .album ? .album : .playlist,
            itemId: item.itemId,
            displayName: item.name,
            displaySubtitle: item.subtitle,
            coverArtId: item.coverArtId,
            coverImage: coverImage,
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
    let namespace: Namespace.ID

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
            GeometryReader { geo in
                CoverArtView(id: album.coverArt ?? album.id, size: Int(geo.size.width * 2))
                    .frame(width: geo.size.width, height: geo.size.width)
                    .cassetteCoverStyle(cornerRadius: CassetteCornerRadius.standard)
            }
            .aspectRatio(1, contentMode: .fit)
            .modifier(ConditionalMatchedTransitionSource(id: album.id, namespace: namespace))
            Text(album.name)
                .font(.cassetteCaption)
                .fontWeight(.semibold)
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
        .task(id: album.id) {
            coverImage = await artworkImageCache.load(coverArtId: album.coverArt ?? album.id)
        }
        .lazyCollectionContextMenu(
            itemType: .album,
            itemId: album.id,
            displayName: album.name,
            displaySubtitle: album.artist ?? "",
            coverArtId: album.coverArt,
            coverImage: coverImage,
            favoriteType: .album
        ) {
            let detail = try await container?.libraryService.album(id: album.id)
            return (detail?.song ?? []).map { DisplayableSong(from: $0) }
        }
    }
}

// MARK: - Zoom transition source modifier

private struct ConditionalMatchedTransitionSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
