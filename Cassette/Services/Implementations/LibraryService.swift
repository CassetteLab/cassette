import Foundation
import SwiftSonic
import OSLog

actor LibraryService: LibraryServiceProtocol {
    private let serverService: any ServerServiceProtocol

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    func artists() async throws -> [ArtistIndex] {
        let client = try await serverService.makeSwiftSonicClient()
        return try await client.getArtists()
    }

    func artist(id: String) async throws -> ArtistID3 {
        let client = try await serverService.makeSwiftSonicClient()
        return try await client.getArtist(id: id)
    }

    func album(id: String) async throws -> AlbumID3 {
        let client = try await serverService.makeSwiftSonicClient()
        return try await client.getAlbum(id: id)
    }

    func playlists() async throws -> [Playlist] {
        let client = try await serverService.makeSwiftSonicClient()
        return try await client.getPlaylists()
    }

    func playlist(id: String) async throws -> PlaylistWithSongs {
        let client = try await serverService.makeSwiftSonicClient()
        return try await client.getPlaylist(id: id)
    }

    func search(_ query: String) async throws -> SearchResult3 {
        let client = try await serverService.makeSwiftSonicClient()
        return try await client.search3(query)
    }

    func coverArtURL(id: String, size: Int?) async -> URL? {
        guard let client = try? await serverService.makeSwiftSonicClient() else { return nil }
        return client.coverArtURL(id: id, size: size)
    }

    func streamURL(songId: String) async -> URL? {
        guard let client = try? await serverService.makeSwiftSonicClient() else { return nil }
        return client.streamURL(id: songId)
    }

    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {
        // TODO(v1.x): verify Navidrome savePlayQueue support; implement best-effort sync
    }

    func getPlayQueue() async throws -> SavedPlayQueue? {
        // TODO(v1.x): implement best-effort queue restore from server
        return nil
    }
}
