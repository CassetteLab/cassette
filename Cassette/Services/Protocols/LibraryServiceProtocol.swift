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

    // TODO(v1.x): verify Navidrome savePlayQueue / getPlayQueue support before relying on these
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws
    func getPlayQueue() async throws -> SavedPlayQueue?
}
