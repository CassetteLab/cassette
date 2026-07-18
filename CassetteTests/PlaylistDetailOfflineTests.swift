// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Stubs

/// Every endpoint throws — PlaylistDetailViewModel's offline paths must never
/// reach the server; loadFromAPI's failure is the trigger under test.
@MainActor
private final class PDLibraryStub: LibraryServiceProtocol {
    /// When set, `playlist(id:)` returns this instead of throwing — used to drive the
    /// empty-but-successful (200, no entries) path that the catch block can't catch.
    var playlistResult: PlaylistWithSongs?
    func playlist(id: String) async throws -> PlaylistWithSongs {
        if let playlistResult { return playlistResult }
        throw URLError(.notConnectedToInternet)
    }
    func playlists() async throws -> [Playlist] { throw URLError(.unknown) }
    func artists() async throws -> [ArtistIndex] { throw URLError(.unknown) }
    func artist(id: String) async throws -> ArtistID3 { throw URLError(.unknown) }
    func album(id: String) async throws -> AlbumID3 { throw URLError(.unknown) }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func search(_ query: String) async throws -> SearchResult3 { throw URLError(.unknown) }
    func coverArtURL(id: String, size: Int?) async -> URL? { nil }
    func streamURL(songId: String) async -> URL? { nil }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw URLError(.unknown) }
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw URLError(.unknown) }
    func getStarred2() async throws -> Starred2 { throw URLError(.unknown) }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func allAlbums() async throws -> [AlbumID3] { throw URLError(.unknown) }
    func allSongs(offset: Int, count: Int) async throws -> [Song] { [] }
    func scrobble(songId: String, submission: Bool) async {}
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func randomSongs(size: Int) async throws -> [Song] { throw URLError(.unknown) }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws { throw URLError(.unknown) }
    func getPlayQueue() async throws -> SavedPlayQueue? { throw URLError(.unknown) }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw URLError(.unknown) }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }
    func findArtist(byName name: String) async -> ArtistID3? { nil }
    func topSongs(artist: String, count: Int) async throws -> [DisplayableSong] { [] }
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong] { [] }
}

/// Serves a configurable LocalPlaylistData; everything else is inert.
@MainActor
private final class PDDownloadStub: DownloadServiceProtocol {
    var playlistData: LocalPlaylistData?

    let progressStream: AsyncStream<[DownloadProgress]> = AsyncStream { $0.finish() }
    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData? { playlistData }
    func localArtistData(artistId: String, artistName: String?, serverId: UUID) async -> LocalArtistData? { nil }
    func backfillPlaylistSongIds(playlistId: String, serverId: UUID, orderedSongIds: [String]) async {}
    func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData? { nil }
    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL? { nil }
    func isDownloaded(songId: String, serverId: UUID) async -> Bool { false }
    func downloadedSongIds(serverId: UUID) async -> Set<String> { [] }
    func localCoverArtURL(forId coverArtId: String) async -> URL? { nil }
    func persistCover(_ data: Data, forId coverArtId: String) async {}
    func removeCover(forId coverArtId: String) async {}
    func garbageCollectOrphanedCovers(referencedIds: Set<String>) async -> Int { 0 }
    func download(song: Song, serverId: UUID) async throws { throw URLError(.unknown) }
    func download(album: AlbumID3, serverId: UUID) async throws { throw URLError(.unknown) }
    func download(playlist: PlaylistWithSongs, serverId: UUID) async throws { throw URLError(.unknown) }
    func isDownloading(songId: String, serverId: UUID) async -> Bool { false }
    func isDownloadingAlbum(_ albumId: String) async -> Bool { false }
    func isDownloadingPlaylist(_ playlistId: String) async -> Bool { false }
    func cancelDownload(songId: String, serverId: UUID) async {}
    func remove(songId: String, serverId: UUID) async throws { throw URLError(.unknown) }
    func remove(albumId: String, serverId: UUID) async throws { throw URLError(.unknown) }
    func remove(playlistId: String, serverId: UUID) async throws { throw URLError(.unknown) }
}

/// All playlist mutations throw — unused by the offline-load paths under test.
@MainActor
private final class PDPlaylistStub: PlaylistServiceProtocol {
    func listPlaylists() async throws -> [Playlist] { throw URLError(.unknown) }
    func getPlaylist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    @discardableResult
    func createPlaylist(name: String, description: String?) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    func renamePlaylist(id: String, newName: String) async throws { throw URLError(.unknown) }
    func updateDescription(id: String, description: String) async throws { throw URLError(.unknown) }
    func addTracks(playlistId: String, songs: [Song]) async throws { throw URLError(.unknown) }
    func removeTracks(playlistId: String, indices: [Int]) async throws { throw URLError(.unknown) }
    func reorderTracks(playlistId: String, orderedSongIds: [String]) async throws { throw URLError(.unknown) }
    func deletePlaylist(id: String, purgeDownloads: Bool) async throws { throw URLError(.unknown) }
}

// MARK: - Tests

@Suite("PlaylistDetailViewModel — offline local fallback")
@MainActor
struct PlaylistDetailOfflineTests {

    private func song(_ id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: "Track \(id)", artist: "Artist", albumId: nil,
            albumName: nil, artistId: nil, genre: nil, duration: 180,
            trackNumber: nil, isDownloaded: true, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private func makeVM(playlistData: LocalPlaylistData?, isOnline: Bool, apiPlaylist: PlaylistWithSongs? = nil) -> PlaylistDetailViewModel {
        let state = ServerState()
        state.isOnline = isOnline
        state.activeServer = ServerSnapshot(from: ServerConfig(
            displayName: "S", baseURL: "https://s.example.com", username: "u", isActive: true
        ))
        let download = PDDownloadStub()
        download.playlistData = playlistData
        let library = PDLibraryStub()
        library.playlistResult = apiPlaylist
        return PlaylistDetailViewModel(
            playlistId: "playlist-1",
            libraryService: library,
            downloadService: download,
            playlistService: PDPlaylistStub(),
            toastService: ToastService(),
            serverState: state
        )
    }

    /// An empty-but-successful playlist payload (200 OK, zero entries) — the WARP/Cloudflare
    /// edge response that returns without throwing.
    private var emptySuccessPlaylist: PlaylistWithSongs {
        PlaylistWithSongs(id: "playlist-1", name: "Road Trip", songCount: 0, duration: 0)
    }

    private var downloadedPlaylist: LocalPlaylistData {
        LocalPlaylistData(
            playlistId: "playlist-1", name: "Road Trip", coverArtId: nil,
            songs: [song("1"), song("2")]
        )
    }

    @Test("downloaded playlist falls back to local when the server call fails (stale isOnline)")
    func downloadedPlaylistFallsBackOnServerFailure() async {
        let vm = makeVM(playlistData: downloadedPlaylist, isOnline: true)
        await vm.load()
        #expect(vm.songs.count == 2)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
        #expect(vm.name == "Road Trip")
    }

    @Test("transient failure with no local copy shows the error, not a false offline state")
    func transientFailureWithoutLocalCopyShowsError() async {
        let vm = makeVM(playlistData: nil, isOnline: true)
        await vm.load()
        #expect(vm.error != nil)
        #expect(vm.isOffline == false)
        #expect(vm.songs.isEmpty)
    }

    @Test("genuinely offline, downloaded playlist loads from local with no server call")
    func offlineDownloadedPlaylistLoadsLocally() async {
        let vm = makeVM(playlistData: downloadedPlaylist, isOnline: false)
        await vm.load()
        #expect(vm.songs.count == 2)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
    }

    @Test("genuinely offline, non-downloaded playlist shows the empty state — no error")
    func offlineNonDownloadedShowsEmptyState() async {
        let vm = makeVM(playlistData: nil, isOnline: false)
        await vm.load()
        #expect(vm.songs.isEmpty)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
    }

    // MARK: - Empty-success (WARP / Cloudflare edge) — the case the throw-only stubs missed

    @Test("empty-success playlist response with a downloaded copy loads local, not Empty")
    func emptySuccessFallsBackToLocal() async {
        let vm = makeVM(playlistData: downloadedPlaylist, isOnline: true, apiPlaylist: emptySuccessPlaylist)
        await vm.load()
        #expect(vm.songs.count == 2)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
        #expect(vm.name == "Road Trip")
    }

    @Test("empty-success playlist with NO downloaded copy stays empty, no error")
    func emptySuccessNoLocalStaysEmpty() async {
        let vm = makeVM(playlistData: nil, isOnline: true, apiPlaylist: emptySuccessPlaylist)
        await vm.load()
        #expect(vm.songs.isEmpty)
        #expect(vm.error == nil)
    }
}
