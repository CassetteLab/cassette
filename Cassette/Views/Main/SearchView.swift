// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic
import SwiftData
import OSLog

// MARK: - WARNING — DO NOT add @Observable / @Query / @Bindable observations to SearchView's body
//
// SearchView owns the .navigationDestination modifiers for the entire search tab.
// Any @Observable, @Query, or @Bindable observation read in this view's body
// (including inside destination closures) will cause SearchView to re-render
// whenever that observed value mutates — for example when destinations load
// artwork or when SearchHistoryService writes to the SwiftData container.
//
// Each re-render re-evaluates all .navigationDestination closures. If SwiftUI
// treats the resulting struct change as a view identity change it discards the
// existing pushed view and inserts a new one, producing a visual layering bug
// where the wrong view appears on top during the push animation.
//
// This bug has regressed three times. The safe pattern:
// - Observations needed only for search results UI → put them in a child view
//   (see SearchSongResultsSection and SearchHistoryListView for the pattern).
// - Values needed by destination views → have the destination read them from
//   its own @Environment, not from a parameter passed through this body.

struct SearchView: View {
    @Binding var searchQuery: String
    @Environment(\.appContainer) private var container
    @State private var viewModel: SearchViewModel?
    @Namespace private var albumZoomNamespace
    @State private var navigatingToHistoryEntry: SearchHistoryEntry? = nil
    @State private var songToAddToPlaylist: DisplayableSong?

    init(searchQuery: Binding<String>) {
        self._searchQuery = searchQuery
    }

    private var serverId: String {
        container?.serverState.activeServer?.id.uuidString ?? ""
    }

    var body: some View {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        Group {
            if trimmed.isEmpty {
                SearchHistoryListView(
                    serverId: serverId,
                    onNavigate: { entry in navigatingToHistoryEntry = entry }
                )
            } else if let vm = viewModel, !vm.isSearching,
                      let results = vm.searchResults, !hasAnyResults(results) {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No results",
                    subtitle: "Try a different search term."
                )
            } else {
                List {
                    if let vm = viewModel {
                        activeSearchContent(vm)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationDestination(for: ArtistID3.self) { artist in
            HistoryRecordingView {
                await container?.searchHistoryService.record(
                    itemId: artist.id, itemType: "artist",
                    displayName: artist.name, coverArtId: artist.coverArt,
                    serverId: serverId
                )
            } content: {
                #if os(macOS)
                ArtistDetailMacOS(artistId: artist.id, artistName: artist.name, coverArtId: artist.coverArt)
                #else
                ArtistDetailView(artist: artist)
                #endif
            }
        }
        .navigationDestination(for: AlbumID3.self) { album in
            HistoryRecordingView {
                await container?.searchHistoryService.record(
                    itemId: album.id, itemType: "album",
                    displayName: album.name, coverArtId: album.coverArt,
                    serverId: serverId
                )
            } content: {
                #if os(macOS)
                AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                #else
                AlbumDetailView(album: album)
                #endif
            }
        }
        .navigationDestination(for: HomeDestination.self) { destination in
            switch destination {
            case .album(let album):
                #if os(macOS)
                AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                #else
                AlbumDetailView(
                    album: album,
                    zoomSourceId: album.id,
                    zoomNamespace: albumZoomNamespace,
                    coverArtId: album.coverArt
                )
                #endif
            case .albumById(let id, let name, _, let coverArtId):
                #if os(macOS)
                AlbumDetailMacOS(albumId: id, albumName: name, coverArtId: coverArtId)
                #else
                AlbumDetailView(
                    albumId: id,
                    albumName: name,
                    zoomSourceId: id,
                    zoomNamespace: albumZoomNamespace,
                    coverArtId: coverArtId
                )
                #endif
            case .artist(let artist):
                #if os(macOS)
                ArtistDetailMacOS(artistId: artist.id, artistName: artist.name, coverArtId: artist.coverArt)
                #else
                ArtistDetailView(artist: artist)
                #endif
            case .artistById(let id, let name, let coverArtId):
                #if os(macOS)
                ArtistDetailMacOS(artistId: id, artistName: name, coverArtId: coverArtId)
                #else
                ArtistDetailView(artistId: id, artistName: name, coverArtId: coverArtId)
                #endif
            default:
                EmptyView()
            }
        }
        .navigationDestination(item: $navigatingToHistoryEntry) { entry in
            switch entry.itemType {
            case "artist":
                #if os(macOS)
                ArtistDetailMacOS(artistId: entry.itemId, artistName: entry.displayName, coverArtId: entry.coverArtId)
                #else
                ArtistDetailView(artistId: entry.itemId, artistName: entry.displayName, coverArtId: entry.coverArtId)
                #endif
            default:
                #if os(macOS)
                AlbumDetailMacOS(albumId: entry.itemId, albumName: entry.displayName, coverArtId: entry.coverArtId)
                #else
                AlbumDetailView(albumId: entry.itemId, albumName: entry.displayName, coverArtId: entry.coverArtId)
                #endif
            }
        }
        .onAppear {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = SearchViewModel(libraryService: svc) }
        }
        .task(id: searchQuery) {
            await viewModel?.search(query: searchQuery)
        }
        .sheet(item: $songToAddToPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
        .cassetteContentWidth()
    }

    // MARK: - Active search state

    @ViewBuilder
    private func activeSearchContent(_ vm: SearchViewModel) -> some View {
        if vm.isSearching {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowSeparator(.hidden)
            .padding(.vertical, CassetteSpacing.xl)
        } else if let error = vm.searchError {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Search Unavailable",
                subtitle: error.localizedDescription,
                action: .init(label: "Retry") { Task { await vm.search(query: searchQuery) } }
            )
            .listRowSeparator(.hidden)
        } else if let results = vm.searchResults, hasAnyResults(results) {
            artistResultsSection(results.artist ?? [])
            albumResultsSection(results.album ?? [])
            SearchSongResultsSection(
                songs: (results.song ?? []).map { DisplayableSong(from: $0) },
                onAddToPlaylist: { s in songToAddToPlaylist = s }
            )
        }
    }

    private func hasAnyResults(_ results: SearchResult3) -> Bool {
        !(results.artist?.isEmpty ?? true) || !(results.album?.isEmpty ?? true) || !(results.song?.isEmpty ?? true)
    }

    @ViewBuilder
    private func artistResultsSection(_ artists: [ArtistID3]) -> some View {
        if !artists.isEmpty {
            Section("Artists") {
                ForEach(artists) { artist in
                    NavigationLink(value: artist) {
                        ArtistRow(artist: artist)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func albumResultsSection(_ albums: [AlbumID3]) -> some View {
        if !albums.isEmpty {
            Section("Albums") {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumRow(
                            albumId: album.id,
                            name: album.name,
                            artist: album.artist,
                            year: album.year,
                            coverArtId: album.coverArt
                        )
                    }
                }
            }
        }
    }

    // MARK: - Song results section (isolated to prevent @Query re-renders in SearchView body)

    private struct SearchSongResultsSection: View {
        let songs: [DisplayableSong]
        let onAddToPlaylist: (DisplayableSong) -> Void

        @Environment(\.appContainer) private var container
        @Query private var allFavorites: [FavoriteRecord]

        private var favoriteSongIds: Set<String> {
            Set(allFavorites.map(\.id))
        }

        var body: some View {
            if !songs.isEmpty {
                Section("Songs") {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        SongRow(
                            song: song,
                            index: index + 1,
                            showCoverArt: true,
                            isFavorite: favoriteSongIds.contains("song:\(song.id)"),
                            onAddToPlaylist: { s in onAddToPlaylist(s) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                do {
                                    try await container?.playerService.play(tracks: songs, startIndex: index)
                                } catch {
                                    Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search history list

    private struct SearchHistoryListView: View {
        let serverId: String
        let onNavigate: (SearchHistoryEntry) -> Void

        @Environment(\.appContainer) private var container
        @Query private var historyEntries: [SearchHistoryEntry]

        init(serverId: String, onNavigate: @escaping (SearchHistoryEntry) -> Void) {
            self.serverId = serverId
            self.onNavigate = onNavigate
            var descriptor = FetchDescriptor<SearchHistoryEntry>(
                sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 50
            _historyEntries = Query(descriptor)
        }

        private var serverHistory: [SearchHistoryEntry] {
            historyEntries.filter { $0.serverId == serverId }
        }

        var body: some View {
            if serverHistory.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "Search your library",
                    subtitle: "Find songs, albums, artists, and playlists from your server."
                )
            } else {
                List {
                    Section {
                        LazyVStack(spacing: 0) {
                            ForEach(serverHistory) { entry in
                                Button {
                                    Task {
                                        await container?.searchHistoryService.record(
                                            itemId: entry.itemId, itemType: entry.itemType,
                                            displayName: entry.displayName, coverArtId: entry.coverArtId,
                                            serverId: serverId
                                        )
                                    }
                                    onNavigate(entry)
                                } label: {
                                    SearchHistoryEntryRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } header: {
                        HStack {
                            Text("Recent")
                                .font(.cassetteSectionTitle)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button("Clear") {
                                Task { await container?.searchHistoryService.clear(serverId: serverId) }
                            }
                            .font(.cassetteBody)
                            .foregroundStyle(Color.cassetteAccent)
                        }
                        .textCase(nil)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - History recording wrapper

    private struct HistoryRecordingView<Content: View>: View {
        let action: () async -> Void
        @ViewBuilder let content: () -> Content
        var body: some View {
            content().task { await action() }
        }
    }
}
