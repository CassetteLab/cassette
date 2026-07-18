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
// This bug has regressed FIVE times. Do not introduce a sixth.
//
// AUDIT (2026-05-27) — SearchHistoryListView @Query cascade: confirmed root cause.
//
// SearchHistoryListView owns @Query<SearchHistoryEntry>. SwiftData's @Query
// re-evaluates whenever mainContext (modelContainer.mainContext) saves, regardless
// of which entity type changed. Two confirmed background drivers:
//
//   Driver 1 — PinService.modelContext IS mainContext. Every pin/unpin anywhere
//   in the app saves mainContext → @Query re-evaluates → SwiftData re-applies
//   all SearchHistoryEntry property values from store through @Model's @Observable
//   setters → coverArtId/serverId fire as "changed" for EVERY in-memory entry.
//
//   Driver 2 — PlaybackSessionService.savePosition() fires every 5 s during
//   playback on an actor-isolated background context. SwiftData auto-merges that
//   save into mainContext → same cascade as Driver 1.
//
// Additionally, SearchHistoryService.record() for a NEW entry merges the insert
// into mainContext, setting all @Model properties via their setters for the first
// time → observation fires once per new history entry (user-triggered).
//
// Fix direction (not applied here): isolate SearchHistoryListView from mainContext
// saves by moving it to a dedicated background context (see planned fix).
//
// Regression 1 — historyEntries @Query in SearchView body
//   Fix: extract into SearchHistoryListView child view (Option C).
// Regression 2 — artworkImageCache @Observable read in destination closures
//   Fix: AlbumDetailView reads its own @Environment(ArtworkImageCache.self).
// Regression 3 — allFavorites @Query in SearchView body
//   Fix: extract into SearchSongResultsSection child view.
// Regression 4 — @Model SearchHistoryEntry held as .navigationDestination(item:) binding
//   SwiftData @Model uses ObjectIdentifier-based Hashable; a concurrent
//   SearchHistoryService write refreshes the managed object and can invalidate the
//   reference, causing SwiftUI to treat the item as new and re-instantiate the
//   destination. Fix: SearchHistoryNavTarget (plain value struct).
// Regression 5 — .navigationDestination(item:) used for a destination that itself
//   pushes further views. The binding-based modifier is re-evaluated by iOS during
//   nested pushes, destroying and re-instantiating the source destination view even
//   when the binding item is a stable value type. Fix: always use
//   .navigationDestination(for: Type.self) backed by NavigationPath for any
//   destination that is part of a multi-level flow.
//
// The safe pattern:
// - Observations needed only for search results UI → put them in a child view.
// - Values needed by destination views → have the destination read them from
//   its own @Environment, not from a parameter passed through this body.
// - Navigation binding items → use plain value types (struct / enum), never @Model.
// - Any destination that can push further → use .navigationDestination(for:) +
//   NavigationPath, never .navigationDestination(item:).

/// Value-type snapshot of a SearchHistoryEntry used as the navigation binding item.
/// Using a plain struct (stable Hashable) avoids the ObjectIdentifier instability of
/// holding a @Model reference in .navigationDestination(item:) — see guard comment above.
struct SearchHistoryNavTarget: Hashable {
    let itemId: String
    let itemType: String
    let displayName: String
    let coverArtId: String?
}

struct SearchView: View {
    @Binding var searchQuery: String
    @Binding var path: NavigationPath
    @Environment(\.appContainer) private var container
    @State private var viewModel: SearchViewModel?
    @Namespace private var albumZoomNamespace
    @State private var songToAddToPlaylist: DisplayableSong?

    init(searchQuery: Binding<String>, path: Binding<NavigationPath>) {
        self._searchQuery = searchQuery
        self._path = path
    }

    private var serverId: String {
        container?.serverState.activeServer?.id.uuidString ?? ""
    }

    var body: some View {
        let _ = Self._printChanges()
        // [DIAG] Measures how often and how quickly body is re-evaluated on search open.
        let _ = Logger.ui.debug("[SEARCH-OPEN] SearchView.body — query='\(searchQuery, privacy: .public)'")
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        Group {
            if trimmed.isEmpty {
                SearchHistoryListView(
                    serverId: serverId,
                    path: $path
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
            case .artistBestOf(let id, let name, let coverArtId):
                ArtistBestOfView(artistId: id, artistName: name, coverArtId: coverArtId)
            default:
                EmptyView()
            }
        }
        .navigationDestination(for: SearchHistoryNavTarget.self) { entry in
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
            // [DIAG] Time the onAppear block (viewModel init is the only work here).
            let t0 = Date()
            Logger.ui.debug("[SEARCH-OPEN] SearchView.onAppear start")
            guard let svc = container?.libraryService else {
                Logger.ui.debug("[SEARCH-OPEN] SearchView.onAppear — no libraryService, early return")
                return
            }
            let wasNil = viewModel == nil
            if viewModel == nil { viewModel = SearchViewModel(libraryService: svc) }
            Logger.ui.debug("[SEARCH-OPEN] SearchView.onAppear done — \(Int(Date().timeIntervalSince(t0) * 1000))ms — viewModel \(wasNil ? "created" : "already existed", privacy: .public)")
        }
        .task(id: searchQuery) {
            // [DIAG] Fires on every searchQuery change including the initial empty-string open.
            // search("") synchronously sets searchResults = nil on MainActor, which can
            // trigger a SwiftUI re-render while the search bar animation is in flight.
            let t0 = Date()
            Logger.ui.debug("[SEARCH-OPEN] task(id:searchQuery) fired — query='\(searchQuery, privacy: .public)'")
            await viewModel?.search(query: searchQuery)
            Logger.ui.debug("[SEARCH-OPEN] task(id:searchQuery) done — \(Int(Date().timeIntervalSince(t0) * 1000))ms")
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
                subtitle: LocalizedStringKey(error.localizedDescription),
                action: .init(label: "Retry") { Task { await vm.search(query: searchQuery) } }
            )
            .listRowSeparator(.hidden)
        } else if let results = vm.searchResults, hasAnyResults(results) {
            artistResultsSection(visibleArtists(from: results))
            albumResultsSection(results.album ?? [])
            SearchSongResultsSection(
                songs: (results.song ?? []).map { DisplayableSong(from: $0) },
                onAddToPlaylist: { s in songToAddToPlaylist = s }
            )
        }
    }

    private func visibleArtists(from results: SearchResult3) -> [ArtistID3] {
        (results.artist ?? []).filter { ($0.albumCount ?? 0) > 0 }
    }

    private func hasAnyResults(_ results: SearchResult3) -> Bool {
        !visibleArtists(from: results).isEmpty || !(results.album?.isEmpty ?? true) || !(results.song?.isEmpty ?? true)
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
        @Binding var path: NavigationPath

        @Environment(\.appContainer) private var container
        @Query private var historyEntries: [SearchHistoryEntry]
        @State private var showClearConfirm = false

        init(serverId: String, path: Binding<NavigationPath>) {
            // [DIAG] Time the Query descriptor construction.
            // Note: the actual SwiftData fetch executes later on the main thread
            // when SwiftUI first renders this view — its cost will not appear here.
            let t0 = Date()
            self.serverId = serverId
            self._path = path
            var descriptor = FetchDescriptor<SearchHistoryEntry>(
                sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 50
            _historyEntries = Query(descriptor)
            Logger.ui.debug("[SEARCH-OPEN] SearchHistoryListView.init done — \(Int(Date().timeIntervalSince(t0) * 1000))ms")
        }

        private var serverHistory: [SearchHistoryEntry] {
            historyEntries.filter { $0.serverId == serverId }
        }

        var body: some View {
            let _ = Self._printChanges()
            // [DIAG] Log raw @Query result count and cost of the in-process serverHistory filter.
            // historyEntries.count > 0 here means the SwiftData fetch already ran (on main thread).
            // If filter time >> 0ms with large historyEntries, add serverId predicate to @Query.
            let bodyStart = CFAbsoluteTimeGetCurrent()
            let history = serverHistory
            let rowsData = history.map { SearchHistoryRowData(entry: $0) }
            let filterMs = Int((CFAbsoluteTimeGetCurrent() - bodyStart) * 1000)
            let _ = Logger.ui.debug("[SEARCH-OPEN] SearchHistoryListView.body — @Query:\(historyEntries.count) server-filtered:\(history.count) filter:\(filterMs)ms")
            let _ = { if filterMs > 16 { Logger.ui.warning("[BODY-SLOW] SearchHistoryListView filter=\(filterMs)ms (main thread)") } }()
            if history.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "Search your library",
                    subtitle: "Find songs, albums, artists, and playlists from your server."
                )
            } else {
                List {
                    Section {
                        LazyVStack(spacing: 0) {
                            ForEach(rowsData) { rowData in
                                Button {
                                    let target = SearchHistoryNavTarget(
                                        itemId: rowData.itemId,
                                        itemType: rowData.itemType,
                                        displayName: rowData.displayName,
                                        coverArtId: rowData.coverArtId
                                    )
                                    Task {
                                        await container?.searchHistoryService.record(
                                            itemId: rowData.itemId, itemType: rowData.itemType,
                                            displayName: rowData.displayName, coverArtId: rowData.coverArtId,
                                            serverId: serverId
                                        )
                                    }
                                    path.append(target)
                                } label: {
                                    SearchHistoryEntryRow(data: rowData)
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
                                showClearConfirm = true
                            }
                            .font(.cassetteBody)
                            .foregroundStyle(Color.cassetteAccent)
                        }
                        .textCase(nil)
                    }
                }
                .listStyle(.plain)
                // [DIAG] Fires after the List is on-screen — gap between body log and this
                // log is the main-thread cost of the @Query fetch + SwiftUI layout pass.
                .onAppear {
                    Logger.ui.debug("[SEARCH-OPEN] SearchHistoryListView appeared — \(history.count) row(s) visible")
                }
                // Clearing search history is destructive with no undo, so gate it behind a confirmation.
                // A centered .alert (popin) is used here — intentionally diverging from the playlist
                // delete's bottom action-sheet. The clear runs ONLY on confirm; Cancel leaves the history
                // intact. .alert is a centered modal on both iOS and macOS.
                .alert("Clear search history?", isPresented: $showClearConfirm) {
                    Button("Clear", role: .destructive) {
                        Task { await container?.searchHistoryService.clear(serverId: serverId) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all your recent searches. This action cannot be undone.")
                }
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
