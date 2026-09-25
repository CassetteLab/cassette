// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Stubs

/// Serves one playlist payload in a fixed server order; nothing else is reachable.
@MainActor
private final class PSLibraryStub: LibraryServiceProtocol {
    var playlistResult: PlaylistWithSongs?
    func playlist(id: String) async throws -> PlaylistWithSongs {
        if let playlistResult { return playlistResult }
        throw URLError(.unknown)
    }
    func coverArtURL(id: String, size: Int?) async -> URL? { nil }
    func streamURL(songId: String) async -> URL? { nil }
    func findArtist(byName name: String) async -> ArtistID3? { nil }
    func scrobble(songId: String, submission: Bool) async {}
    func playlists() async throws -> [Playlist] { throw URLError(.unknown) }
    func artists() async throws -> [ArtistIndex] { throw URLError(.unknown) }
    func artist(id: String) async throws -> ArtistID3 { throw URLError(.unknown) }
    func album(id: String) async throws -> AlbumID3 { throw URLError(.unknown) }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func search(_ query: String) async throws -> SearchResult3 { throw URLError(.unknown) }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw URLError(.unknown) }
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw URLError(.unknown) }
    func getStarred2() async throws -> Starred2 { throw URLError(.unknown) }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func allAlbums() async throws -> [AlbumID3] { throw URLError(.unknown) }
    func allSongs(offset: Int, count: Int) async throws -> [Song] { [] }
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func songsByGenre(_ genre: String, count: Int) async throws -> [Song] { [] }
    func randomSongs(size: Int) async throws -> [Song] { throw URLError(.unknown) }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws { throw URLError(.unknown) }
    func getPlayQueue() async throws -> SavedPlayQueue? { throw URLError(.unknown) }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw URLError(.unknown) }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }
    func topSongs(artist: String, count: Int) async throws -> [DisplayableSong] { [] }
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong] { [] }
}

@MainActor
private final class PSDownloadStub: DownloadServiceProtocol {
    nonisolated let progressStream: AsyncStream<[DownloadProgress]> = AsyncStream { $0.finish() }
    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL? { nil }
    func isDownloaded(songId: String, serverId: UUID) async -> Bool { false }
    func downloadedSongIds(serverId: UUID) async -> Set<String> { [] }
    func localCoverArtURL(forId coverArtId: String) async -> URL? { nil }
    func persistCover(_ data: Data, forId coverArtId: String) async {}
    func removeCover(forId coverArtId: String) async {}
    func clearStreamingCovers() async -> Int { 0 }
    func healMissingCovers(referencedIds: Set<String>) async -> Int { 0 }
    func garbageCollectOrphanedCovers(referencedIds: Set<String>) async -> Int { 0 }
    func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData? { nil }
    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData? { nil }
    func backfillPlaylistSongIds(playlistId: String, serverId: UUID, orderedSongIds: [String]) async {}
    func download(song: Song, serverId: UUID) async throws {}
    func download(album: AlbumID3, serverId: UUID) async throws {}
    func download(playlist: PlaylistWithSongs, serverId: UUID) async throws {}
    func remove(songId: String, serverId: UUID) async throws {}
    func remove(albumId: String, serverId: UUID) async throws {}
    func remove(playlistId: String, serverId: UUID) async throws {}
    func removeAll() async throws {}
    func cancel(songId: String, serverId: UUID) async {}
    func cancelDownload(songId: String, serverId: UUID) async {}
    func isDownloading(songId: String, serverId: UUID) async -> Bool { false }
    func localArtistData(artistId: String, artistName: String?, serverId: UUID) async -> LocalArtistData? { nil }
    func cancelAlbumDownload(_ albumId: String) async {}
    func cancelPlaylistDownload(_ playlistId: String) async {}
    func isDownloadingAlbum(_ albumId: String) async -> Bool { false }
    func isDownloadingPlaylist(_ playlistId: String) async -> Bool { false }
}

@MainActor
private final class PSPlaylistStub: PlaylistServiceProtocol {
    func listPlaylists() async throws -> [Playlist] { throw URLError(.unknown) }
    func getPlaylist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    @discardableResult
    func createPlaylist(name: String, description: String?) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    func renamePlaylist(id: String, newName: String) async throws {}
    func updateDescription(id: String, description: String) async throws {}
    func addTracks(playlistId: String, songs: [Song]) async throws {}
    func removeTracks(playlistId: String, indices: [Int]) async throws {}
    func reorderTracks(playlistId: String, orderedSongIds: [String]) async throws {}
    func deletePlaylist(id: String, purgeDownloads: Bool) async throws {}
}

// MARK: - Tests

/// Add Music replaces a playlist's whole track list. It used to be handed the DISPLAYED ids,
/// so adding one song to a sorted playlist rewrote the playlist in the sorted order — for
/// everyone, permanently. These drive a real view model to prove the list it now hands over is
/// the server's order.
@Suite("Playlist sort — Add Music sends the server's order")
@MainActor
struct PlaylistSortAddMusicTests {

    /// Server order is deliberately not alphabetical, so a title sort has to move things.
    private let serverOrder = ["s3", "s1", "s2"]
    private let titles = ["s1": "Aurora", "s2": "Bramble", "s3": "Cinder"]

    /// A unique playlist id per test. The sort is persisted per playlist in UserDefaults, so
    /// sharing one id would make these race each other when the suite runs in parallel.
    private func makeLoadedVM(
        playlistId: String = "playlist-\(UUID().uuidString)"
    ) async -> (vm: PlaylistDetailViewModel, cleanUp: () -> Void) {
        let state = ServerState()
        state.isOnline = true
        state.activeServer = ServerSnapshot(from: ServerConfig(
            displayName: "S", baseURL: "https://s.example.com", username: "u", isActive: true
        ))
        let library = PSLibraryStub()
        library.playlistResult = PlaylistWithSongs(
            id: playlistId,
            name: "Mixtape",
            songCount: serverOrder.count,
            duration: 0,
            entry: serverOrder.map { Song(id: $0, title: titles[$0] ?? $0) }
        )
        let vm = PlaylistDetailViewModel(
            playlistId: playlistId,
            libraryService: library,
            downloadService: PSDownloadStub(),
            playlistService: PSPlaylistStub(),
            toastService: ToastService(),
            serverState: state
        )
        await vm.load()
        return (vm, { UserDefaults.standard.removeObject(forKey: "cassette.playlistSort.\(playlistId)") })
    }

    @Test("loading preserves the server's order")
    func loadsInServerOrder() async {
        let (vm, cleanUp) = await makeLoadedVM()
        defer { cleanUp() }
        #expect(vm.songs.map(\.id) == serverOrder)
        #expect(vm.playlistOrderedIds == serverOrder)
    }

    @Test("sorting by title changes the display and leaves the playlist order alone")
    func sortingIsDisplayOnly() async {
        let (vm, cleanUp) = await makeLoadedVM()
        defer { cleanUp() }
        vm.sort = .title

        #expect(vm.songs.map(\.id) == ["s1", "s2", "s3"], "the list is alphabetical")
        #expect(vm.playlistOrderedIds == serverOrder, "the playlist's own order is untouched")
    }

    /// The assertion that matters: this is exactly the array Add Music builds and sends to
    /// `reorderTracks`, which replaces the playlist wholesale.
    @Test("adding a track to a sorted playlist sends server order plus the new track last")
    func addMusicSendsServerOrderPlusNewTrack() async {
        let (vm, cleanUp) = await makeLoadedVM()
        defer { cleanUp() }
        vm.sort = .title
        #expect(vm.songs.map(\.id) == ["s1", "s2", "s3"], "precondition: a sort really is active")

        // AddMusicCommitter.commit: finalIds = existingTrackIds + addedSongs.map(\.id)
        let sent = vm.playlistOrderedIds + ["s4"]

        #expect(sent == ["s3", "s1", "s2", "s4"])
        #expect(sent != vm.songs.map(\.id) + ["s4"], "must not be the displayed order")
        #expect(Array(sent.dropLast()) == serverOrder, "the existing tracks keep their order")
        #expect(sent.last == "s4", "the new track goes last")
    }

    @Test("with no sort the two orders agree, so behaviour is unchanged")
    func unsortedIsUnchanged() async {
        let (vm, cleanUp) = await makeLoadedVM()
        defer { cleanUp() }
        #expect(vm.playlistOrderedIds + ["s4"] == vm.songs.map(\.id) + ["s4"])
    }
}
