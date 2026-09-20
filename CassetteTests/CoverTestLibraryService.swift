// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
@testable import Cassette

/// Enough of `LibraryServiceProtocol` to construct an `ArtworkImageCache`.
///
/// The cover-cache tests exercise only the on-disk side, so every network call here is
/// unreachable by construction: `coverArtURL` returns nil, which makes the cache's fetch path
/// bail before it ever reaches a session. Anything else trapping would be a test-design bug,
/// so the rest throws rather than returning plausible empty values.
final class CoverTestLibraryService: LibraryServiceProtocol {
    struct Unused: Error {}

    func coverArtURL(id: String, size: Int?) async -> URL? { nil }
    func streamURL(songId: String) async -> URL? { nil }
    func findArtist(byName name: String) async -> ArtistID3? { nil }
    func scrobble(songId: String, submission: Bool) async {}

    func artists() async throws -> [ArtistIndex] { throw Unused() }
    func artist(id: String) async throws -> ArtistID3 { throw Unused() }
    func album(id: String) async throws -> AlbumID3 { throw Unused() }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { throw Unused() }
    func playlists() async throws -> [Playlist] { throw Unused() }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw Unused() }
    func search(_ query: String) async throws -> SearchResult3 { throw Unused() }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw Unused() }
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws { throw Unused() }
    func getStarred2() async throws -> Starred2 { throw Unused() }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { throw Unused() }
    func allAlbums() async throws -> [AlbumID3] { throw Unused() }
    func allSongs(offset: Int, count: Int) async throws -> [Song] { throw Unused() }
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw Unused() }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw Unused() }
    func randomSongs(size: Int) async throws -> [Song] { throw Unused() }
    func songsByGenre(_ genre: String, count: Int) async throws -> [Song] { throw Unused() }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { throw Unused() }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { throw Unused() }
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws { throw Unused() }
    func getPlayQueue() async throws -> SavedPlayQueue? { throw Unused() }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw Unused() }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { throw Unused() }
    func topSongs(artist: String, count: Int) async throws -> [DisplayableSong] { throw Unused() }
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong] { throw Unused() }
}
