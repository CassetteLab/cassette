// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

protocol LibraryServiceProtocol: AnyObject, Sendable {
    func artists() async throws -> [ArtistIndex]
    func artist(id: String) async throws -> ArtistID3
    func album(id: String) async throws -> AlbumID3
    func playlists() async throws -> [Playlist]
    func playlist(id: String) async throws -> PlaylistWithSongs
    func search(_ query: String) async throws -> SearchResult3
    func coverArtURL(id: String, size: Int?) async -> URL?
    func streamURL(songId: String) async -> URL?

    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws
    func getStarred2() async throws -> Starred2
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3]
    func allAlbums() async throws -> [AlbumID3]
    func lyrics(artist: String?, title: String?) async throws -> Lyrics?

    // TODO(v1.x): verify Navidrome savePlayQueue / getPlayQueue support before relying on these
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws
    func getPlayQueue() async throws -> SavedPlayQueue?
}
