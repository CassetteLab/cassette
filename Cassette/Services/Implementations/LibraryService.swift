// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

actor LibraryService: LibraryServiceProtocol {
    private let serverService: any ServerServiceProtocol
    private var cachedClient: SwiftSonicClient?
    private var cachedServerId: UUID?

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    private func client() async throws -> SwiftSonicClient {
        let activeId = await MainActor.run { serverService.state.activeServer?.id }
        if let cached = cachedClient, cachedServerId == activeId, activeId != nil {
            return cached
        }
        let fresh = try await serverService.makeSwiftSonicClient()
        cachedClient = fresh
        cachedServerId = activeId
        return fresh
    }

    func artists() async throws -> [ArtistIndex] {
        try await client().getArtists()
    }

    func artist(id: String) async throws -> ArtistID3 {
        try await client().getArtist(id: id)
    }

    func album(id: String) async throws -> AlbumID3 {
        try await client().getAlbum(id: id)
    }

    func playlists() async throws -> [Playlist] {
        try await client().getPlaylists()
    }

    func playlist(id: String) async throws -> PlaylistWithSongs {
        try await client().getPlaylist(id: id)
    }

    func search(_ query: String) async throws -> SearchResult3 {
        try await client().search3(query)
    }

    func coverArtURL(id: String, size: Int?) async -> URL? {
        guard let c = try? await client() else { return nil }
        return c.coverArtURL(id: id, size: size)
    }

    func streamURL(songId: String) async -> URL? {
        guard let c = try? await client() else { return nil }
        return c.streamURL(id: songId)
    }

    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        try await client().star(songIds: songIds, albumIds: albumIds, artistIds: artistIds)
    }

    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        try await client().unstar(songIds: songIds, albumIds: albumIds, artistIds: artistIds)
    }

    func getStarred2() async throws -> Starred2 {
        try await client().getStarred2()
    }

    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] {
        try await client().getAlbumList2(type: .newest, size: size)
    }

    func allAlbums() async throws -> [AlbumID3] {
        try await client().getAlbumList2(type: .alphabeticalByName, size: 500)
    }

    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {
        // TODO(v1.x): verify Navidrome savePlayQueue support; implement best-effort sync
    }

    func getPlayQueue() async throws -> SavedPlayQueue? {
        // TODO(v1.x): implement best-effort queue restore from server
        return nil
    }
}
