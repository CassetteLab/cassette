// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
import SwiftSonic
@testable import Cassette

/// Exercises the REAL `DownloadService.localArtistData` reconstruction against an in-memory store,
/// then the ViewModel fallback on top of it — the same two layers the album and playlist offline
/// suites cover.
@Suite("Offline artist — real localArtistData round-trip")
@MainActor
struct LocalArtistDataTests {

    private func makeService() throws -> (service: DownloadService, container: ModelContainer, serverId: UUID) {
        let container = try ModelContainer.cassette(inMemory: true)
        let service = DownloadService(
            serverService: MockServerService(),
            modelContainer: container,
            toastService: ToastService()
        )
        return (service, container, UUID())
    }

    private func insertTrack(
        _ container: ModelContainer,
        songId: String,
        serverId: UUID,
        albumId: String?,
        artistId: String?,
        artist: String?,
        track: Int
    ) {
        container.mainContext.insert(
            DownloadedTrack(
                songId: songId,
                serverId: serverId,
                albumId: albumId,
                filePath: "\(serverId.uuidString)/\(songId).mp3",
                fileSize: 1234,
                mimeType: "audio/mpeg",
                title: "Track \(songId)",
                artist: artist,
                artistId: artistId,
                album: albumId,
                trackNumber: track
            )
        )
    }

    @Test("groups an artist's downloaded tracks into albums, tracks ordered within each")
    func groupsIntoAlbums() async throws {
        let (service, container, sid) = try makeService()
        insertTrack(container, songId: "s2", serverId: sid, albumId: "al-1", artistId: "ar-1", artist: "Orelsan", track: 2)
        insertTrack(container, songId: "s1", serverId: sid, albumId: "al-1", artistId: "ar-1", artist: "Orelsan", track: 1)
        insertTrack(container, songId: "s3", serverId: sid, albumId: "al-2", artistId: "ar-1", artist: "Orelsan", track: 1)
        try container.mainContext.save()

        let data = await service.localArtistData(artistId: "ar-1", artistName: "Orelsan", serverId: sid)
        #expect(data?.albums.count == 2)
        #expect(data?.albums.first(where: { $0.albumId == "al-1" })?.songs.map(\.id) == ["s1", "s2"])
        #expect(data?.tracks.count == 3)
    }

    @Test("returns nil when nothing of the artist is downloaded")
    func nilWhenNothingDownloaded() async throws {
        let (service, container, sid) = try makeService()
        insertTrack(container, songId: "s1", serverId: sid, albumId: "al-1", artistId: "other", artist: "Someone", track: 1)
        try container.mainContext.save()

        let data = await service.localArtistData(artistId: "ar-1", artistName: "Orelsan", serverId: sid)
        #expect(data == nil)
    }

    @Test("matches by name only for tracks whose server omitted the artist id")
    func nameFallbackOnlyWhenIdMissing() async throws {
        let (service, container, sid) = try makeService()
        // No artistId: name match is the only way to reach it.
        insertTrack(container, songId: "s1", serverId: sid, albumId: "al-1", artistId: nil, artist: "orelsan", track: 1)
        // Correctly tagged as somebody else, but sharing the display name — must NOT be pulled in.
        insertTrack(container, songId: "s2", serverId: sid, albumId: "al-2", artistId: "ar-other", artist: "Orelsan", track: 1)
        try container.mainContext.save()

        let data = await service.localArtistData(artistId: "ar-1", artistName: "Orelsan", serverId: sid)
        #expect(data?.tracks.map(\.id) == ["s1"])
    }

    @Test("ignores tracks belonging to a different server")
    func ignoresOtherServer() async throws {
        let (service, container, sid) = try makeService()
        insertTrack(container, songId: "s1", serverId: UUID(), albumId: "al-1", artistId: "ar-1", artist: "Orelsan", track: 1)
        try container.mainContext.save()

        let data = await service.localArtistData(artistId: "ar-1", artistName: "Orelsan", serverId: sid)
        #expect(data == nil)
    }

    @Test("tracks without an albumId don't crash the grouping and are simply not listed as albums")
    func tracksWithoutAlbumId() async throws {
        let (service, container, sid) = try makeService()
        insertTrack(container, songId: "s1", serverId: sid, albumId: nil, artistId: "ar-1", artist: "Orelsan", track: 1)
        try container.mainContext.save()

        let data = await service.localArtistData(artistId: "ar-1", artistName: "Orelsan", serverId: sid)
        // A match exists, so the artist is not nil — but there is no album to show.
        #expect(data != nil)
        #expect(data?.albums.isEmpty == true)
    }
}

// MARK: - ViewModel fallback

@MainActor
private final class ARLibraryStub: LibraryServiceProtocol {
    /// When set, `artist(id:)` returns this instead of throwing — drives the empty-but-successful path.
    var artistResult: ArtistID3?
    func artist(id: String) async throws -> ArtistID3 {
        if let artistResult { return artistResult }
        throw URLError(.notConnectedToInternet)
    }
    func album(id: String) async throws -> AlbumID3 { throw URLError(.unknown) }
    func artists() async throws -> [ArtistIndex] { throw URLError(.unknown) }
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

@MainActor
private final class ARDownloadStub: DownloadServiceProtocol {
    var artistData: LocalArtistData?

    let progressStream: AsyncStream<[DownloadProgress]> = AsyncStream { $0.finish() }
    func localArtistData(artistId: String, artistName: String?, serverId: UUID) async -> LocalArtistData? { artistData }
    func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData? { nil }
    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData? { nil }
    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL? { nil }
    func isDownloaded(songId: String, serverId: UUID) async -> Bool { false }
    func downloadedSongIds(serverId: UUID) async -> Set<String> { [] }
    func localCoverArtURL(forId coverArtId: String) async -> URL? { nil }
    func persistCover(_ data: Data, forId coverArtId: String) async {}
    func removeCover(forId coverArtId: String) async {}
    func garbageCollectOrphanedCovers(referencedIds: Set<String>) async -> Int { 0 }
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

@Suite("ArtistDetailViewModel — offline local fallback")
@MainActor
struct ArtistDetailOfflineTests {

    private func song(_ id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: "Track \(id)", artist: "Orelsan", albumId: "al-1",
            albumName: "Album", artistId: "ar-1", genre: nil, duration: 180,
            trackNumber: nil, isDownloaded: true, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private var downloadedArtist: LocalArtistData {
        LocalArtistData(
            artistId: "ar-1",
            artistName: "Orelsan",
            coverArtId: "cover-1",
            albums: [
                LocalAlbumData(
                    albumId: "al-1", albumName: "Civilisation", artistName: "Orelsan",
                    coverArtId: "cover-1", songs: [song("s1"), song("s2")]
                )
            ],
            tracks: [song("s1"), song("s2")]
        )
    }

    private func makeVM(
        artistData: LocalArtistData?,
        isOnline: Bool,
        apiArtist: ArtistID3? = nil
    ) -> ArtistDetailViewModel {
        let state = ServerState()
        state.isOnline = isOnline
        state.activeServer = ServerSnapshot(from: ServerConfig(
            displayName: "S", baseURL: "https://s.example.com", username: "u", isActive: true
        ))
        let download = ARDownloadStub()
        download.artistData = artistData
        let library = ARLibraryStub()
        library.artistResult = apiArtist
        return ArtistDetailViewModel(
            artistId: "ar-1",
            artistName: "Orelsan",
            libraryService: library,
            downloadService: download,
            recommendationService: RecommendationService(providers: []),
            imageResolver: ExternalArtistImageResolver(),
            serverState: state
        )
    }

    @Test("offline rebuilds the artist from downloads")
    func offlineRebuildsFromDownloads() async {
        let vm = makeVM(artistData: downloadedArtist, isOnline: false)
        await vm.load()
        #expect(vm.isOffline)
        #expect(vm.artist?.name == "Orelsan")
        #expect(vm.artist?.album?.count == 1)
        #expect(vm.artist?.album?.first?.songCount == 2)
        #expect(vm.offlineTracks.count == 2)
        #expect(vm.error == nil)
    }

    @Test("falls back to the downloaded copy when the server call fails with a stale isOnline")
    func fallsBackOnServerFailure() async {
        let vm = makeVM(artistData: downloadedArtist, isOnline: true)
        await vm.load()
        #expect(vm.isOffline)
        #expect(vm.artist?.album?.count == 1)
        #expect(vm.error == nil)
    }

    @Test("surfaces the error when the server fails and nothing is downloaded")
    func errorWhenNoLocalCopy() async {
        let vm = makeVM(artistData: nil, isOnline: true)
        await vm.load()
        #expect(vm.artist == nil)
        #expect(vm.error != nil)
        #expect(vm.isOffline == false)
    }

    @Test("offline with nothing downloaded leaves an empty artist and no error")
    func offlineWithoutDownloads() async {
        let vm = makeVM(artistData: nil, isOnline: false)
        await vm.load()
        #expect(vm.artist == nil)
        #expect(vm.error == nil)
    }

    @Test("a 200 with no albums prefers the downloaded copy over an empty screen")
    func emptySuccessPrefersLocal() async {
        let empty = ArtistID3(id: "ar-1", name: "Orelsan", album: [])
        let vm = makeVM(artistData: downloadedArtist, isOnline: true, apiArtist: empty)
        await vm.load()
        #expect(vm.isOffline)
        #expect(vm.artist?.album?.count == 1)
    }

    @Test("the online-only sections stop loading offline so they collapse instead of showing skeletons")
    func offlineClearsLoadingFlags() async {
        let vm = makeVM(artistData: downloadedArtist, isOnline: false)
        await vm.load()
        await vm.loadTopSongs()
        await vm.loadLikedSongs()
        await vm.loadSimilarArtists()
        await vm.loadArtistInfo()
        #expect(vm.isLoadingTopSongs == false)
        #expect(vm.isLoadingLikedSongs == false)
        #expect(vm.isLoadingSimilarArtists == false)
        #expect(vm.isLoadingArtistInfo == false)
        #expect(vm.topSongs.isEmpty)
        #expect(vm.similarArtists.isEmpty)
        #expect(vm.biography == nil)
    }
}
