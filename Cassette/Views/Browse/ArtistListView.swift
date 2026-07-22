// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic

struct ArtistListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistListViewModel?
    @AppStorage("cassette.artistSort") private var artistSort: ArtistSort = .name
    @AppStorage("cassette.artistListGrid") private var gridLayout = false

    private let gridColumns = [GridItem(.adaptive(minimum: 110, maximum: 150), spacing: CassetteSpacing.l)]

    var body: some View {
        Group {
            if let vm = viewModel {
                browseContent(vm)
            } else {
                LoadingStateView()
            }
        }
        .cassetteContentWidth()
        .navigationTitle("Artists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 2) {
                    ArtistSortMenu(sort: $artistSort)
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
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = ArtistListViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func browseContent(_ vm: ArtistListViewModel) -> some View {
        if vm.isLoading && vm.indexes.isEmpty {
            LoadingStateView()
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
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.indexes.isEmpty {
            EmptyStateView(
                systemImage: "music.mic",
                title: "No Artists",
                subtitle: "Your library appears to be empty."
            )
        } else if gridLayout {
            artistsGrid(vm)
        } else if artistSort == .name {
            indexedList(vm)
        } else {
            flatList(vm)
        }
    }

    /// Alphabetical indexed list with section headers + A–Z jump bar (Name sort, list mode).
    private func indexedList(_ vm: ArtistListViewModel) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(vm.indexes, id: \.name) { index in
                    Section(index.name) {
                        ForEach(index.artist) { artist in
                            NavigationLink(value: HomeDestination.artist(artist)) {
                                ArtistRow(artist: artist)
                            }
                        }
                    }
                    .id(index.name)
                }
            }
            .listStyle(.plain)
            .miniPlayerBottomMargin()
            .refreshable { await vm.load() }
            #if os(iOS)
            .safeAreaInset(edge: .trailing, spacing: 0) {
                if vm.indexes.count >= 5 {
                    AlphabetJumpBar(
                        availableLetters: Set(vm.indexes.map(\.name)),
                        onLetterTap: { letter in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(letter, anchor: .top)
                            }
                        }
                    )
                    .padding(.trailing, 4)
                }
            }
            #endif
        }
    }

    /// Flat list in the chosen order (Album Count sort, list mode).
    private func flatList(_ vm: ArtistListViewModel) -> some View {
        List(artistSort.sorted(vm.indexes.flatMap(\.artist))) { artist in
            NavigationLink(value: HomeDestination.artist(artist)) {
                ArtistRow(artist: artist)
            }
        }
        .listStyle(.plain)
        .miniPlayerBottomMargin()
        .refreshable { await vm.load() }
    }

    /// Grid of artist avatars in the chosen order.
    private func artistsGrid(_ vm: ArtistListViewModel) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: CassetteSpacing.l) {
                ForEach(artistSort.sorted(vm.indexes.flatMap(\.artist))) { artist in
                    NavigationLink(value: HomeDestination.artist(artist)) {
                        ArtistGridCard(artist: artist)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(CassetteSpacing.l)
        }
        .refreshable { await vm.load() }
        .miniPlayerBottomMargin()
    }
}

// MARK: - Offline Browse

nonisolated struct OfflineAlbumSummary: Sendable, Identifiable, Hashable {
    let albumId: String
    let albumName: String
    let artistName: String?
    let coverArtId: String?
    let trackCount: Int
    var id: String { albumId }
}

nonisolated struct OfflineArtistSummary: Sendable, Identifiable, Hashable {
    let name: String
    let albums: [OfflineAlbumSummary]
    /// Server artist id when the downloaded tracks carried one. Present → the row can open the real
    /// artist screen (which rebuilds itself from downloads); absent → it falls back to the flat album list.
    var artistId: String?
    var coverArtId: String?
    var id: String { artistId ?? name }
}

/// Derives the offline artist/album hierarchy from DownloadedTrack — the single source of truth
/// for all offline content, regardless of whether it came from an album or a playlist download.
private struct OfflineBrowseContent: View {
    let serverId: UUID
    @Query private var tracks: [DownloadedTrack]

    init(serverId: UUID) {
        self.serverId = serverId
        let sid = serverId
        _tracks = Query(
            filter: #Predicate<DownloadedTrack> { track in track.serverId == sid }
        )
    }

    /// One entry per album, tagged with the artist id when the tracks carried one.
    private struct AlbumEntry {
        let summary: OfflineAlbumSummary
        let artistId: String?
    }

    private var artistSummaries: [OfflineArtistSummary] {
        let withAlbum = tracks.filter { $0.albumId != nil }
        let byAlbum = Dictionary(grouping: withAlbum) { $0.albumId! }
        let entries = byAlbum.map { albumId, albumTracks -> AlbumEntry in
            let first = albumTracks[0]
            return AlbumEntry(
                summary: OfflineAlbumSummary(
                    albumId: albumId,
                    albumName: first.album ?? albumId,
                    artistName: first.artist,
                    coverArtId: first.coverArtId,
                    trackCount: albumTracks.count
                ),
                artistId: albumTracks.compactMap(\.artistId).first
            )
        }
        // Group on the artist id when it's there, falling back to a case-folded name. Grouping on the raw
        // name (as this did) split one artist into several rows on any casing/spelling inconsistency.
        let byArtist = Dictionary(grouping: entries) { entry in
            entry.artistId ?? "name:\(entry.summary.artistName?.lowercased() ?? "")"
        }
        return byArtist.map { _, entries in
            let albums = entries.map(\.summary).sorted {
                $0.albumName.localizedCaseInsensitiveCompare($1.albumName) == .orderedAscending
            }
            return OfflineArtistSummary(
                name: entries.first?.summary.artistName ?? String(localized: "Unknown Artist"),
                albums: albums,
                artistId: entries.compactMap(\.artistId).first,
                coverArtId: albums.first?.coverArtId
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        if tracks.isEmpty {
            EmptyStateView(
                systemImage: "wifi.slash",
                title: "You're Offline",
                subtitle: "No downloaded music available. Download albums or playlists while online to listen offline."
            )
        } else {
            List {
                Section("Downloaded Artists") {
                    ForEach(artistSummaries) { artist in
                        // With an artist id the real artist screen can rebuild itself from downloads —
                        // covers, album grid, working Play. Without one, the flat album list is all we can offer.
                        NavigationLink(value: destination(for: artist)) {
                            OfflineArtistRow(artist: artist)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func destination(for artist: OfflineArtistSummary) -> HomeDestination {
        guard let artistId = artist.artistId else { return .offlineArtist(artist) }
        return .artistById(id: artistId, name: artist.name, coverArtId: artist.coverArtId)
    }
}

private struct OfflineArtistRow: View {
    let artist: OfflineArtistSummary

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            // The album cover stands in for the artist photo: artist art is only on disk if it was
            // fetched while browsing, whereas an album cover ships with every download.
            CoverArtView(id: artist.coverArtId ?? artist.id, size: 88)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.s))
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.cassetteCellTitle)
                    .lineLimit(1)
                Text("\(artist.albums.count) albums")
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, CassetteSpacing.xs)
    }
}

struct OfflineArtistAlbumsView: View {
    let artist: OfflineArtistSummary

    var body: some View {
        List {
            ForEach(artist.albums) { album in
                NavigationLink(value: HomeDestination.offlineAlbum(album)) {
                    AlbumRow(
                        albumId: album.albumId,
                        name: album.albumName,
                        artist: album.artistName,
                        year: nil,
                        coverArtId: album.coverArtId
                    )
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayModeInline()
        .cassetteContentWidth()
    }
}
