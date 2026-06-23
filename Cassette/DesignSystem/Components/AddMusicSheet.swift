// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftData
import SwiftSonic
import OSLog

// MARK: - Selection model

/// Running multi-select state for the add-music flow. Shared down the navigation stack via `.environment`
/// so every drilled-in list toggles the same selection without prop-drilling. `existingIds` are the tracks
/// already in the playlist — they show as disabled "already added" and are never offered/added again.
@MainActor
@Observable
final class AddMusicSelection {
    private(set) var selected: [DisplayableSong] = []
    let existingIds: Set<String>

    init(existingIds: [String]) { self.existingIds = Set(existingIds) }

    var count: Int { selected.count }
    func isSelected(_ song: DisplayableSong) -> Bool { selected.contains { $0.id == song.id } }
    func isExisting(_ song: DisplayableSong) -> Bool { existingIds.contains(song.id) }

    func toggle(_ song: DisplayableSong) {
        guard !isExisting(song) else { return }
        if let idx = selected.firstIndex(where: { $0.id == song.id }) {
            selected.remove(at: idx)
        } else {
            selected.append(song)
        }
    }

    /// Bulk-add a whole album / artist / playlist; skips already-in-playlist and already-selected songs.
    func add(_ songs: [DisplayableSong]) {
        for song in songs where !isExisting(song) && !isSelected(song) {
            selected.append(song)
        }
    }

    /// Count of songs in `songs` that are still addable (not existing, not already selected).
    func addableCount(in songs: [DisplayableSong]) -> Int {
        songs.filter { !isExisting($0) && !isSelected($0) }.count
    }
}

// MARK: - Navigation routes

/// Value-based routes for the single navigationDestination at the sheet root — heterogeneous drill targets.
enum AddMusicRoute: Hashable {
    case allAlbums
    case recentlyAdded
    case recentlyPlayed
    case allArtists
    case allPlaylists
    case favorites
    case downloads
    case albumSongs(id: String, name: String)
    case artistAlbums(id: String, name: String)
    case playlistSongs(id: String, name: String)
}

/// Where a song-list leaf loads its songs from. One picker view, one online call per case.
enum AddMusicSongSource: Hashable {
    case album(id: String)
    case artist(id: String)
    case playlist(id: String)
    case favorites
}

// MARK: - Sheet root

/// Apple-Music-style "Add to <playlist>" browse + multi-select sheet. Cross-platform (iOS + macOS). Reuses
/// the Home "Library" navigation layout (Playlists / Albums / Artists / Favorites / Downloads / Recently
/// added) + Recently played, in a SELECTION mode: drill to songs, tap `+` to add, commit adds them all at
/// once. Browse only — no create/edit playlist here. The actual commit (atomic full-list replace + first-track
/// color derivation + comment guard) is `onCommit`, injected by the caller so this view stays presentation.
struct AddMusicSheet: View {
    let playlistName: String
    /// Commit handler: receives the ordered new-song selection. Returns when the server replace is done.
    let onCommit: ([DisplayableSong]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: AddMusicSelection
    @State private var searchText = ""
    @State private var isSaving = false

    init(playlistName: String, existingTrackIds: [String], onCommit: @escaping ([DisplayableSong]) async -> Void) {
        self.playlistName = playlistName
        self.onCommit = onCommit
        _selection = State(initialValue: AddMusicSelection(existingIds: existingTrackIds))
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    libraryRoot
                } else {
                    AddMusicSearchResults(query: searchText)
                }
            }
            .navigationDestination(for: AddMusicRoute.self) { route in
                destination(for: route)
            }
            .navigationTitle("Add to \(playlistName)")
            .navigationBarTitleDisplayModeInline()
            .toolbar { toolbar }
        }
        .searchable(text: $searchText, prompt: "Find in library")
        .environment(selection)
    }

    // MARK: Root (Home "Library" layout, browse-only)

    private var libraryRoot: some View {
        List {
            Section {
                AddMusicLibraryRow(title: "Playlists", systemImage: "music.note.list", route: .allPlaylists)
                AddMusicLibraryRow(title: "Albums", systemImage: "square.stack", route: .allAlbums)
                AddMusicLibraryRow(title: "Artists", systemImage: "music.mic", route: .allArtists)
                AddMusicLibraryRow(title: "Favorites", systemImage: "heart.fill", route: .favorites)
                AddMusicLibraryRow(title: "Downloads", systemImage: "arrow.down.circle.fill", route: .downloads)
            } header: {
                Text("Library").font(.cassetteSectionTitle).textCase(nil).foregroundStyle(.primary)
            }
            Section {
                AddMusicLibraryRow(title: "Recently Added", systemImage: "clock", route: .recentlyAdded)
                AddMusicLibraryRow(title: "Recently Played", systemImage: "play.circle", route: .recentlyPlayed)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AddMusicRoute) -> some View {
        switch route {
        case .allAlbums:        AddMusicAlbumList(mode: .all, title: "Albums")
        case .recentlyAdded:    AddMusicAlbumList(mode: .recentlyAdded, title: "Recently Added")
        case .recentlyPlayed:   AddMusicAlbumList(mode: .recentlyPlayed, title: "Recently Played")
        case .allArtists:       AddMusicArtistList()
        case .allPlaylists:     AddMusicPlaylistList()
        case .favorites:        AddMusicSongPicker(source: .favorites, title: "Favorites")
        case .downloads:        AddMusicDownloadsList()
        case let .albumSongs(id, name):    AddMusicSongPicker(source: .album(id: id), title: name)
        case let .artistAlbums(id, name):  AddMusicArtistAlbumList(artistId: id, title: name)
        case let .playlistSongs(id, name): AddMusicSongPicker(source: .playlist(id: id), title: name)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: { CircleToolbarLabel(systemName: "xmark") }
                .buttonStyle(.plain)
                .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task {
                        isSaving = true
                        await onCommit(selection.selected)
                        isSaving = false
                        dismiss()
                    }
                } label: {
                    CircleToolbarLabel(systemName: "checkmark", filled: selection.count > 0)
                }
                .buttonStyle(.plain)
                .disabled(selection.count == 0)
            }
        }
    }
}

// MARK: - Library row

private struct AddMusicLibraryRow: View {
    let title: String
    let systemImage: String
    let route: AddMusicRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: CassetteSpacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.cassetteAccent)
                        .frame(width: 30, height: 30)
                    Image(systemName: systemImage)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                Text(title).font(.cassetteCellTitle)
            }
        }
    }
}

// MARK: - Song row (the leaf: tap `+` to select)

private struct AddMusicSongRow: View {
    let song: DisplayableSong
    @Environment(AddMusicSelection.self) private var selection

    var body: some View {
        Button {
            selection.toggle(song)
        } label: {
            HStack(spacing: CassetteSpacing.m) {
                CoverArtView(id: song.coverArtId ?? song.id, size: 80, cornerRadius: CassetteCornerRadius.standard)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.cassetteCellTitle).lineLimit(1)
                    if let artist = song.artist {
                        Text(artist).font(.cassetteCellSubtitle).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: CassetteSpacing.s)
                trailingIcon
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selection.isExisting(song))
    }

    @ViewBuilder
    private var trailingIcon: some View {
        if selection.isExisting(song) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tertiary)
        } else if selection.isSelected(song) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.cassetteAccent)
        } else {
            Image(systemName: "plus.circle").foregroundStyle(Color.cassetteAccent)
        }
    }
}

// MARK: - Song picker (leaf list for album / artist-all / playlist / favorites)

private struct AddMusicSongPicker: View {
    let source: AddMusicSongSource
    let title: String

    @Environment(\.appContainer) private var container
    @Environment(AddMusicSelection.self) private var selection
    @State private var songs: [DisplayableSong] = []
    @State private var phase: AddMusicLoadPhase = .loading

    var body: some View {
        List {
            if !songs.isEmpty {
                Section {
                    Button {
                        selection.add(songs)
                    } label: {
                        Label("Add all (\(selection.addableCount(in: songs)))", systemImage: "plus.circle.fill")
                    }
                    .disabled(selection.addableCount(in: songs) == 0)
                }
                Section {
                    ForEach(songs) { AddMusicSongRow(song: $0) }
                }
            } else {
                AddMusicPhaseView(phase: phase, emptyText: "No songs")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayModeInline()
        .task(id: source) { await load() }
    }

    private func load() async {
        guard let svc = container?.libraryService else { phase = .failed; return }
        phase = .loading
        do {
            switch source {
            case let .album(id):
                songs = (try await svc.album(id: id).song ?? []).map { DisplayableSong(from: $0) }
            case let .artist(id):
                songs = try await svc.fetchAllTracks(forArtistID: id)
            case let .playlist(id):
                songs = (try await svc.playlist(id: id).entry ?? []).map { DisplayableSong(from: $0) }
            case .favorites:
                songs = (try await svc.getStarred2().song ?? []).map { DisplayableSong(from: $0) }
            }
            phase = songs.isEmpty ? .empty : .loaded
        } catch {
            Logger.library.error("[ADD-MUSIC] song load failed: \(error, privacy: .public)")
            phase = .failed
        }
    }
}

// MARK: - Album list (all / recently-added / recently-played)

private struct AddMusicAlbumList: View {
    enum Mode: Hashable { case all, recentlyAdded, recentlyPlayed }
    let mode: Mode
    let title: String

    @Environment(\.appContainer) private var container
    @State private var albums: [AlbumID3] = []
    @State private var phase: AddMusicLoadPhase = .loading

    var body: some View {
        List {
            if albums.isEmpty {
                AddMusicPhaseView(phase: phase, emptyText: "No albums")
            } else {
                ForEach(albums) { album in
                    NavigationLink(value: AddMusicRoute.albumSongs(id: album.id, name: album.name)) {
                        AddMusicCoverRow(coverArtId: album.coverArt ?? album.id,
                                         title: album.name, subtitle: album.artist)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayModeInline()
        .task { await load() }
    }

    private func load() async {
        guard let svc = container?.libraryService else { phase = .failed; return }
        phase = .loading
        do {
            switch mode {
            case .all:            albums = try await svc.allAlbums()
            case .recentlyAdded:  albums = try await svc.recentlyAddedAlbums(size: 100)
            case .recentlyPlayed: albums = try await svc.recentlyPlayedAlbums(size: 100)
            }
            phase = albums.isEmpty ? .empty : .loaded
        } catch {
            Logger.library.error("[ADD-MUSIC] album list failed: \(error, privacy: .public)")
            phase = .failed
        }
    }
}

// MARK: - Artist list -> artist albums -> album songs

private struct AddMusicArtistList: View {
    @Environment(\.appContainer) private var container
    @State private var artists: [ArtistID3] = []
    @State private var phase: AddMusicLoadPhase = .loading

    var body: some View {
        List {
            if artists.isEmpty {
                AddMusicPhaseView(phase: phase, emptyText: "No artists")
            } else {
                ForEach(artists) { artist in
                    NavigationLink(value: AddMusicRoute.artistAlbums(id: artist.id, name: artist.name)) {
                        AddMusicCoverRow(coverArtId: artist.coverArt ?? artist.id,
                                         title: artist.name, subtitle: nil)
                    }
                }
            }
        }
        .navigationTitle("Artists")
        .navigationBarTitleDisplayModeInline()
        .task { await load() }
    }

    private func load() async {
        guard let svc = container?.libraryService else { phase = .failed; return }
        phase = .loading
        do {
            artists = try await svc.artists().flatMap { $0.artist }
            phase = artists.isEmpty ? .empty : .loaded
        } catch {
            Logger.library.error("[ADD-MUSIC] artist list failed: \(error, privacy: .public)")
            phase = .failed
        }
    }
}

private struct AddMusicArtistAlbumList: View {
    let artistId: String
    let title: String

    @Environment(\.appContainer) private var container
    @Environment(AddMusicSelection.self) private var selection
    @State private var albums: [AlbumID3] = []
    @State private var allSongs: [DisplayableSong] = []
    @State private var phase: AddMusicLoadPhase = .loading

    var body: some View {
        List {
            if !allSongs.isEmpty {
                Section {
                    Button {
                        selection.add(allSongs)
                    } label: {
                        Label("Add all songs (\(selection.addableCount(in: allSongs)))", systemImage: "plus.circle.fill")
                    }
                    .disabled(selection.addableCount(in: allSongs) == 0)
                }
            }
            if albums.isEmpty {
                AddMusicPhaseView(phase: phase, emptyText: "No albums")
            } else {
                Section {
                    ForEach(albums) { album in
                        NavigationLink(value: AddMusicRoute.albumSongs(id: album.id, name: album.name)) {
                            AddMusicCoverRow(coverArtId: album.coverArt ?? album.id,
                                             title: album.name, subtitle: album.year.map(String.init))
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayModeInline()
        .task { await load() }
    }

    private func load() async {
        guard let svc = container?.libraryService else { phase = .failed; return }
        phase = .loading
        do {
            albums = try await svc.artist(id: artistId).album ?? []
            phase = albums.isEmpty ? .empty : .loaded
            allSongs = (try? await svc.fetchAllTracks(forArtistID: artistId)) ?? []
        } catch {
            Logger.library.error("[ADD-MUSIC] artist albums failed: \(error, privacy: .public)")
            phase = .failed
        }
    }
}

// MARK: - Playlist list -> playlist songs

private struct AddMusicPlaylistList: View {
    @Environment(\.appContainer) private var container
    @State private var playlists: [Playlist] = []
    @State private var phase: AddMusicLoadPhase = .loading

    var body: some View {
        List {
            if playlists.isEmpty {
                AddMusicPhaseView(phase: phase, emptyText: "No playlists")
            } else {
                ForEach(playlists) { playlist in
                    NavigationLink(value: AddMusicRoute.playlistSongs(id: playlist.id, name: playlist.name)) {
                        AddMusicCoverRow(coverArtId: playlist.coverArt ?? playlist.id,
                                         title: playlist.name,
                                         subtitle: "\(playlist.songCount) song\(playlist.songCount == 1 ? "" : "s")")
                    }
                }
            }
        }
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayModeInline()
        .task { await load() }
    }

    private func load() async {
        guard let svc = container?.libraryService else { phase = .failed; return }
        phase = .loading
        do {
            playlists = try await svc.playlists()
            phase = playlists.isEmpty ? .empty : .loaded
        } catch {
            Logger.library.error("[ADD-MUSIC] playlist list failed: \(error, privacy: .public)")
            phase = .failed
        }
    }
}

// MARK: - Downloads (offline SwiftData source)

private struct AddMusicDownloadsList: View {
    @Environment(AddMusicSelection.self) private var selection
    @Query(sort: \DownloadedTrack.title) private var tracks: [DownloadedTrack]

    private var songs: [DisplayableSong] { tracks.map { DisplayableSong(from: $0) } }

    var body: some View {
        List {
            if songs.isEmpty {
                AddMusicPhaseView(phase: .empty, emptyText: "No downloads")
            } else {
                Section {
                    Button {
                        selection.add(songs)
                    } label: {
                        Label("Add all (\(selection.addableCount(in: songs)))", systemImage: "plus.circle.fill")
                    }
                    .disabled(selection.addableCount(in: songs) == 0)
                }
                Section {
                    ForEach(songs) { AddMusicSongRow(song: $0) }
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayModeInline()
    }
}

// MARK: - Search results

private struct AddMusicSearchResults: View {
    let query: String

    @Environment(\.appContainer) private var container
    @State private var result: SearchResult3?
    @State private var phase: AddMusicLoadPhase = .loading

    private var songs: [DisplayableSong] { (result?.song ?? []).map { DisplayableSong(from: $0) } }

    var body: some View {
        List {
            if let result {
                if let albums = result.album, !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums) { album in
                            NavigationLink(value: AddMusicRoute.albumSongs(id: album.id, name: album.name)) {
                                AddMusicCoverRow(coverArtId: album.coverArt ?? album.id,
                                                 title: album.name, subtitle: album.artist)
                            }
                        }
                    }
                }
                if let artists = result.artist, !artists.isEmpty {
                    Section("Artists") {
                        ForEach(artists) { artist in
                            NavigationLink(value: AddMusicRoute.artistAlbums(id: artist.id, name: artist.name)) {
                                AddMusicCoverRow(coverArtId: artist.coverArt ?? artist.id,
                                                 title: artist.name, subtitle: nil)
                            }
                        }
                    }
                }
                if !songs.isEmpty {
                    Section("Songs") {
                        ForEach(songs) { AddMusicSongRow(song: $0) }
                    }
                }
                if (result.album?.isEmpty ?? true) && (result.artist?.isEmpty ?? true) && songs.isEmpty {
                    AddMusicPhaseView(phase: .empty, emptyText: "No results")
                }
            } else {
                AddMusicPhaseView(phase: phase, emptyText: "No results")
            }
        }
        .task(id: query) { await search() }
    }

    private func search() async {
        guard let svc = container?.libraryService else { phase = .failed; return }
        // Light debounce so each keystroke doesn't fire a search3 call.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        phase = .loading
        do {
            result = try await svc.search(query)
            phase = .loaded
        } catch {
            Logger.library.error("[ADD-MUSIC] search failed: \(error, privacy: .public)")
            phase = .failed
        }
    }
}

// MARK: - Shared row + phase helpers

private struct AddMusicCoverRow: View {
    let coverArtId: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: CassetteSpacing.m) {
            CoverArtView(id: coverArtId, size: 80, cornerRadius: CassetteCornerRadius.standard)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.cassetteCellTitle).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.cassetteCellSubtitle).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

private enum AddMusicLoadPhase { case loading, loaded, empty, failed }

private struct AddMusicPhaseView: View {
    let phase: AddMusicLoadPhase
    let emptyText: String

    var body: some View {
        switch phase {
        case .loading:
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowSeparator(.hidden)
        case .empty, .loaded:
            Text(emptyText)
                .font(.cassetteCellSubtitle).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowSeparator(.hidden)
        case .failed:
            Text("Couldn't load")
                .font(.cassetteCellSubtitle).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowSeparator(.hidden)
        }
    }
}

// MARK: - Commit (atomic replace + R1 comment guard + first-track derivation)

/// Commits an add-music selection through the SINGLE shared path used by every entry point (iOS edit "+",
/// iOS detail, macOS): ONE atomic full-list replace (current tracks + new selection), the R1 comment guard
/// (re-assert a non-empty comment AFTER the replace), and — the critical bit — the empty→first-track color
/// derivation. When the playlist went from empty to its first track on a gradient cover whose color was still
/// the neutral default, the color is derived from the first added track via the SAME `PlaylistGradientResolver`
/// hook the cover re-pick uses (never a parallel path that would skip derivation/caching). Shape + user-pick
/// flag are preserved; later adds never re-derive (the resolver result is frozen in the cover store).
@MainActor
enum AddMusicCommitter {
    static func commit(
        addedSongs: [DisplayableSong],
        playlistId: String,
        serverId: UUID,
        existingTrackIds: [String],
        currentComment: String,
        container: AppContainer,
        colorExtractor: DominantColorExtractor
    ) async {
        guard !addedSongs.isEmpty else { return }
        let wasEmpty = existingTrackIds.isEmpty

        // Atomic full-list replace — the SINGLE track-mutation path (same primitive as reorder/multi-remove).
        // The picker disables already-in-playlist songs, so the selection never collides with existingTrackIds
        // and a plain append is dedup-safe. NOT a naive incremental songIdToAdd.
        let finalIds = existingTrackIds + addedSongs.map(\.id)
        do {
            try await container.playlistService.reorderTracks(playlistId: playlistId, orderedSongIds: finalIds)
        } catch {
            Logger.playlist.error("[ADD-MUSIC] atomic replace failed: \(error, privacy: .public)")
            container.toastService.showError("Couldn't add to playlist")
            return
        }

        // R1 guard: re-assert a non-empty comment AFTER the replace (createPlaylist replace doesn't carry it).
        // No name re-assert (omitted = unchanged).
        let trimmedComment = currentComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComment.isEmpty {
            try? await container.playlistService.updateDescription(id: playlistId, description: trimmedComment)
        }

        await deriveFirstTrackCoverIfNeeded(
            wasEmpty: wasEmpty,
            firstSong: addedSongs.first,
            playlistId: playlistId,
            serverId: serverId,
            container: container,
            colorExtractor: colorExtractor
        )
    }

    /// Piège #1 — the empty→first-track color derivation, shared by `commit` (detail entry points) AND the
    /// EditPlaylistSheet commit (its "+" appends locally, then its Done persists). Only on empty→first-track,
    /// only when the cover is a gradient spec (an empty playlist's gradient color is necessarily the neutral
    /// default — there was no track to derive from). Photo covers have no spec → skipped. Routes through the
    /// SAME PlaylistGradientResolver hook the re-pick uses, so caching + the neutral fallback stay consistent.
    static func deriveFirstTrackCoverIfNeeded(
        wasEmpty: Bool,
        firstSong: DisplayableSong?,
        playlistId: String,
        serverId: UUID,
        container: AppContainer,
        colorExtractor: DominantColorExtractor
    ) async {
        guard wasEmpty, let firstSong, firstSong.coverArtId != nil else { return }
        let store = PlaylistCoverStore(modelContainer: container.modelContainer)
        guard let choice = store.choice(playlistId: playlistId, serverId: serverId),
              let spec = choice.spec else { return }
        let derived = await PlaylistGradientResolver.resolve(
            form: spec.shape,
            firstTrackCoverArtId: firstSong.coverArtId,
            artworkImageCache: container.artworkImageCache,
            colorExtractor: colorExtractor
        )
        let manager = PlaylistCoverManager(
            serverState: container.serverState,
            serverService: container.serverService,
            downloadService: container.downloadService,
            artworkImageCache: container.artworkImageCache,
            coverVersionRegistry: container.coverVersionRegistry
        )
        _ = await manager.applyGradientCover(derived, playlistId: playlistId)
        // Preserve the existing user-pick flag so the cover-store overwrite guard never blocks the derived save.
        store.save(derived, playlistId: playlistId, serverId: serverId, isUserPicked: choice.isUserPicked)
    }
}
