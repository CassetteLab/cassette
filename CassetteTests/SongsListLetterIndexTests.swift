// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Stubs

/// Serves `library` through `allSongs` in pages; nothing else is reachable.
@MainActor
private final class SLLibraryStub: LibraryServiceProtocol {
    var library: [Song] = []
    func playlist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
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
    func allSongs(offset: Int, count: Int) async throws -> [Song] {
        guard offset < library.count else { return [] }
        return Array(library[offset..<min(offset + count, library.count)])
    }
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
private final class SLDownloadStub: DownloadServiceProtocol {
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

// MARK: - Tests

/// The A–Z jump bar's targets are built once, off-main, with the sorted list. They used to be
/// derived in the view on every render — a full pass over a list that can hold 200k songs.
@Suite("Songs list — precomputed A–Z index")
@MainActor
struct SongsListLetterIndexTests {

    private func makeLoadedVM(titles: [String]) async -> SongsListViewModel {
        let state = ServerState()
        state.isOnline = true
        let library = SLLibraryStub()
        library.library = titles.enumerated().map { Song(id: "s\($0.offset)", title: $0.element) }
        let vm = SongsListViewModel(
            libraryService: library,
            downloadService: SLDownloadStub(),
            toastService: ToastService(),
            serverState: state
        )
        await vm.load(sort: .title)
        return vm
    }

    @Test("each letter points at its first row in the sorted list")
    func firstRowPerLetter() async {
        let vm = await makeLoadedVM(titles: ["banana", "Apple", "cherry", "42", "apricot"])

        let sortedTitles = vm.displaySongs.map(\.title)
        #expect(vm.titleLetterIndex.count == 4)
        for (letter, index) in vm.titleLetterIndex {
            #expect(alphabetFirstLetter(of: sortedTitles[index]) == letter)
            // No earlier row starts with the same letter.
            #expect(sortedTitles[..<index].allSatisfy { alphabetFirstLetter(of: $0) != letter })
        }
    }

    @Test("an empty library has no letters")
    func emptyLibrary() async {
        let vm = await makeLoadedVM(titles: [])
        #expect(vm.titleLetterIndex.isEmpty)
    }
}
