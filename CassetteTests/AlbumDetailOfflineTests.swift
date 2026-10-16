// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Stubs

/// Every endpoint throws — AlbumDetailViewModel's offline paths must never
/// reach the server; loadFromAPI's failure is the trigger under test.
@MainActor
private final class ADLibraryStub: LibraryServiceProtocol {
    /// When set, `album(id:)` returns this instead of throwing — used to drive the
    /// empty-but-successful (200, no songs) path that the catch block can't catch.
    var albumResult: AlbumID3?
    /// Fired as the API call is entered — i.e. after `load()` has done whatever it does first.
    /// Lets a test observe the screen's state during the window the server is still thinking,
    /// with no sleeping or polling.
    var onAlbumCalled: (() -> Void)?
    private(set) var albumCallCount = 0
    func album(id: String) async throws -> AlbumID3 {
        albumCallCount += 1
        onAlbumCalled?()
        if let albumResult { return albumResult }
        throw URLError(.notConnectedToInternet)
    }
    func artists() async throws -> [ArtistIndex] { throw URLError(.unknown) }
    func artist(id: String) async throws -> ArtistID3 { throw URLError(.unknown) }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func playlists() async throws -> [Playlist] { throw URLError(.unknown) }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
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
    func songsByGenre(_ genre: String, count: Int) async throws -> [Song] { [] }
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

/// Serves a configurable LocalAlbumData; everything else is inert.
@MainActor
private final class ADDownloadStub: DownloadServiceProtocol {
    var albumData: LocalAlbumData?

    let progressStream: AsyncStream<[DownloadProgress]> = AsyncStream { $0.finish() }
    func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData? { albumData }
    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL? { nil }
    func isDownloaded(songId: String, serverId: UUID) async -> Bool { false }
    func downloadedSongIds(serverId: UUID) async -> Set<String> { [] }
    func localCoverArtURL(forId coverArtId: String) async -> URL? { nil }
    func persistCover(_ data: Data, forId coverArtId: String) async {}
    func removeCover(forId coverArtId: String) async {}
    func clearStreamingCovers() async -> Int { 0 }
    func healMissingCovers(referencedIds: Set<String>) async -> Int { 0 }
    func garbageCollectOrphanedCovers(referencedIds: Set<String>) async -> Int { 0 }
    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData? { nil }
    func localArtistData(artistId: String, artistName: String?, serverId: UUID) async -> LocalArtistData? { nil }
    func backfillPlaylistSongIds(playlistId: String, serverId: UUID, orderedSongIds: [String]) async {}
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

// MARK: - Tests

@Suite("AlbumDetailViewModel — offline local fallback")
@MainActor
struct AlbumDetailOfflineTests {

    private func song(_ id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: "Track \(id)", artist: "Artist", albumId: "album-1",
            albumName: "Album", artistId: nil, genre: nil, duration: 180,
            trackNumber: nil, isDownloaded: true, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private func makeVM(albumData: LocalAlbumData?, isOnline: Bool, apiAlbum: AlbumID3? = nil) -> AlbumDetailViewModel {
        makeParts(albumData: albumData, isOnline: isOnline, apiAlbum: apiAlbum).vm
    }

    private func makeParts(
        albumData: LocalAlbumData?, isOnline: Bool, apiAlbum: AlbumID3? = nil
    ) -> (vm: AlbumDetailViewModel, library: ADLibraryStub, download: ADDownloadStub) {
        let state = ServerState()
        state.isOnline = isOnline
        state.activeServer = ServerSnapshot(from: ServerConfig(
            displayName: "S", baseURL: "https://s.example.com", username: "u", isActive: true
        ))
        let download = ADDownloadStub()
        download.albumData = albumData
        let library = ADLibraryStub()
        library.albumResult = apiAlbum
        let vm = AlbumDetailViewModel(
            albumId: "album-1",
            libraryService: library,
            downloadService: download,
            toastService: ToastService(),
            serverState: state
        )
        return (vm, library, download)
    }

    /// Builds a genuine, empty `AlbumID3` (200 OK, no songs) through SwiftSonic's real
    /// decoder driven by the canned-response transport — the WARP/Cloudflare edge case.
    private func emptySuccessAlbum() async throws -> AlbumID3 {
        let json = Data(#"""
        {"subsonic-response":{"status":"ok","version":"1.16.1","album":{"id":"album-1","name":"Album","artist":"Artist","artistId":"ar-1","songCount":0,"duration":0,"created":"2024-01-01T00:00:00.000Z","coverArt":"al-1","song":[]}}}
        """#.utf8)
        let client = SwiftSonicClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://stub.example.com")!, username: "u", password: "p"
            ),
            transport: StubHTTPTransport(outcome: .response(data: json, statusCode: 200)),
            retryPolicy: .none
        )
        return try await client.getAlbum(id: "album-1")
    }

    private var downloadedAlbum: LocalAlbumData {
        LocalAlbumData(
            albumId: "album-1", albumName: "Album", artistName: "Artist",
            coverArtId: nil, songs: [song("1"), song("2")]
        )
    }

    @Test("downloaded album falls back to local when the server call fails (stale isOnline)")
    func downloadedAlbumFallsBackOnServerFailure() async {
        let vm = makeVM(albumData: downloadedAlbum, isOnline: true)
        await vm.load()
        #expect(vm.songs.count == 2)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
        #expect(vm.albumName == "Album")
    }

    @Test("transient failure with no local copy shows the error, not a false offline state")
    func transientFailureWithoutLocalCopyShowsError() async {
        let vm = makeVM(albumData: nil, isOnline: true)
        await vm.load()
        #expect(vm.error != nil)
        #expect(vm.isOffline == false)
        #expect(vm.songs.isEmpty)
    }

    @Test("genuinely offline, downloaded album loads from local with no server call")
    func offlineDownloadedAlbumLoadsLocally() async {
        let vm = makeVM(albumData: downloadedAlbum, isOnline: false)
        await vm.load()
        #expect(vm.songs.count == 2)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
    }

    @Test("genuinely offline, non-downloaded album shows the empty state — no error")
    func offlineNonDownloadedShowsEmptyState() async {
        let vm = makeVM(albumData: nil, isOnline: false)
        await vm.load()
        #expect(vm.songs.isEmpty)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
    }

    // MARK: - Empty-success (WARP / Cloudflare edge) — the case the throw-only stubs missed

    @Test("empty-success album response with a downloaded copy loads local, not empty")
    func emptySuccessAlbumFallsBackToLocal() async throws {
        let empty = try await emptySuccessAlbum()
        let vm = makeVM(albumData: downloadedAlbum, isOnline: true, apiAlbum: empty)
        await vm.load()
        #expect(vm.songs.count == 2)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
    }

    @Test("empty-success album with NO downloaded copy stays empty, no error")
    func emptySuccessAlbumNoLocalStaysEmpty() async throws {
        let empty = try await emptySuccessAlbum()
        let vm = makeVM(albumData: nil, isOnline: true, apiAlbum: empty)
        await vm.load()
        #expect(vm.songs.isEmpty)
        #expect(vm.error == nil)
    }

    // MARK: - Head start: the downloaded copy goes up before the server answers
    //
    // `isOnline` only means an interface exists. On a network that resolves but never answers
    // (airplane mode leaves Wi-Fi associated) the request burns its whole timeout on every
    // retry, and the screen used to sit on a skeleton for that entire minute with the tracks
    // already on the device.

    @Test("online, the downloaded copy is already on screen while the server is still thinking")
    func localCopyIsShownBeforeTheAPIAnswers() async throws {
        let parts = makeParts(albumData: downloadedAlbum, isOnline: true, apiAlbum: try await fullSuccessAlbum())
        var observed: (songs: Int, name: String, offline: Bool)?
        parts.library.onAlbumCalled = { [vm = parts.vm] in
            observed = (vm.songs.count, vm.albumName, vm.isOffline)
        }
        await parts.vm.load()

        let seen = try #require(observed)
        #expect(seen.songs == 2, "the downloaded tracks should be readable during the wait")
        #expect(seen.name == "Album", "and the header filled in, not blank")
        // The screen must not wear the offline badge while the server may still answer:
        // that is what hides the download controls and unlinks the artist.
        #expect(seen.offline == false)
    }

    @Test("a successful response replaces the head start and clears the offline flag")
    func apiResultWinsOverTheHeadStart() async throws {
        let vm = makeVM(albumData: downloadedAlbum, isOnline: true, apiAlbum: try await fullSuccessAlbum())
        await vm.load()
        #expect(vm.songs.count == 3, "the catalog list, not the two downloaded tracks")
        #expect(vm.isOffline == false)
        #expect(vm.error == nil)
    }

    @Test("a reload does not swap the loaded list for the smaller downloaded copy mid-flight")
    func reloadKeepsWhatIsAlreadyOnScreen() async throws {
        let parts = makeParts(albumData: downloadedAlbum, isOnline: true, apiAlbum: try await fullSuccessAlbum())
        await parts.vm.load()
        #expect(parts.vm.songs.count == 3)

        var songsWhenCalled: Int?
        parts.library.onAlbumCalled = { [vm = parts.vm] in songsWhenCalled = vm.songs.count }
        await parts.vm.load()

        #expect(parts.library.albumCallCount == 2)
        #expect(songsWhenCalled == 3, "the head start is for an empty screen only")
    }

    /// A genuine 200 with three songs, decoded by SwiftSonic itself — one more than the
    /// downloaded copy, so the two lists can be told apart.
    private func fullSuccessAlbum() async throws -> AlbumID3 {
        let json = Data(#"""
        {"subsonic-response":{"status":"ok","version":"1.16.1","album":{"id":"album-1","name":"Album","artist":"Artist","artistId":"ar-1","songCount":3,"duration":600,"created":"2024-01-01T00:00:00.000Z","coverArt":"al-1","song":[{"id":"1","title":"One","duration":200},{"id":"2","title":"Two","duration":200},{"id":"3","title":"Three","duration":200}]}}}
        """#.utf8)
        let client = SwiftSonicClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://stub.example.com")!, username: "u", password: "p"
            ),
            transport: StubHTTPTransport(outcome: .response(data: json, statusCode: 200)),
            retryPolicy: .none
        )
        return try await client.getAlbum(id: "album-1")
    }
}
