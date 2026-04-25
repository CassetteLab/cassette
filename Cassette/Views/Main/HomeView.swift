// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic

struct HomeView: View {
    @Environment(\.appContainer) private var container
    @Query(sort: \PinnedItem.sortOrder) private var pinnedItems: [PinnedItem]
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CassetteSpacing.xl) {
                if !pinnedItems.isEmpty {
                    pinnedSection
                }
                librarySection
                if let vm = viewModel {
                    recentSection(vm)
                }
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
                    if !pinnedItems.isEmpty {
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
        .onAppear { localPinnedItems = pinnedItems }
        .onChange(of: pinnedItems.count) { _, _ in localPinnedItems = pinnedItems }
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
                ForEach(localPinnedItems) { item in
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

    // MARK: - Recently Added section

    @ViewBuilder
    private func recentSection(_ vm: HomeViewModel) -> some View {
        if !vm.recentAlbums.isEmpty || vm.isLoading {
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
    }
}

// MARK: - HomePinnedCard

private struct HomePinnedCard: View {
    let item: PinnedItem

    @Environment(\.appContainer) private var container

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
                    .lineLimit(2)
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
        .contextMenu {
            Button(role: .destructive) {
                container?.pinService.unpin(itemType: PinnedItemType(rawValue: item.itemType) ?? .album, itemId: item.itemId)
            } label: {
                Label("Unpin from Home", systemImage: "pin.slash")
            }
        }
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
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CassetteSpacing.m)
            .padding(.vertical, CassetteSpacing.m)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HomeAlbumCell

private struct HomeAlbumCell: View {
    let album: AlbumID3

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
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let artist = album.artist {
                Text(artist)
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
