// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Integration mock infrastructure

@MainActor
private final class RSITransport: ListenBrainzTransport {
    private var queue: [(Data, HTTPURLResponse)] = []

    func enqueue(data: Data = Data(), status: Int) {
        let resp = HTTPURLResponse(
            url: URL(string: "https://api.listenbrainz.org")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        queue.append((data, resp))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !queue.isEmpty else { throw URLError(.timedOut) }
        return queue.removeFirst()
    }
}

@MainActor
private final class RSIKeychain: KeychainServiceProtocol {
    private var storage: [String: Data] = [:]

    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        storage[key] = try JSONEncoder().encode(value)
    }

    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        guard let data = storage[key] else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func delete(forKey key: String) async throws {
        storage[key] = nil
    }
}

private struct RSIMockProvider: RecommendationProvider {
    let albumResults: [AlbumRecommendation]
    let artistResults: [SimilarArtistRecommendation]

    init(albums: [AlbumRecommendation] = [], artists: [SimilarArtistRecommendation] = []) {
        self.albumResults = albums
        self.artistResults = artists
    }

    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation] { albumResults }
    func similarArtists(toArtistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] { artistResults }
}

private let integrationJSON = Data("""
{
  "payload": {
    "releases": [
      {
        "artist_credit_name": "LB Artist",
        "release_name": "LB Album",
        "release_date": "2026-05-01",
        "release_group_mbid": "lb-rg-mbid"
      }
    ]
  }
}
""".utf8)

private let artistStubInt = SimilarArtistRecommendation(id: "sub-a1", name: "Subsonic Artist", coverArt: nil, inLibrary: true, mbid: nil)

@MainActor
private final class RSILibraryNullStub: LibraryServiceProtocol {
    func artists() async throws -> [ArtistIndex] { throw URLError(.unknown) }
    func artist(id: String) async throws -> ArtistID3 { throw URLError(.unknown) }
    func album(id: String) async throws -> AlbumID3 { throw URLError(.unknown) }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func playlists() async throws -> [Playlist] { throw URLError(.unknown) }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    func search(_ query: String) async throws -> SearchResult3 { throw URLError(.unknown) }
    func coverArtURL(id: String, size: Int?) async -> URL? { nil }
    func streamURL(songId: String) async -> URL? { nil }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {}
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {}
    func getStarred2() async throws -> Starred2 { throw URLError(.unknown) }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func allAlbums() async throws -> [AlbumID3] { throw URLError(.unknown) }
    func scrobble(songId: String, submission: Bool) async {}
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { throw URLError(.unknown) }
    func randomSongs(size: Int) async throws -> [Song] { throw URLError(.unknown) }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { throw URLError(.unknown) }
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {}
    func getPlayQueue() async throws -> SavedPlayQueue? { nil }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw URLError(.unknown) }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }
    func findArtist(byName name: String) async -> ArtistID3? { nil }
    func topSongs(artist: String, count: Int) async throws -> [DisplayableSong] { [] }
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong] { [] }
}

private func makeLBComponents(serviceTransport: any ListenBrainzTransport, providerTransport: any ListenBrainzTransport) -> (ListenBrainzRecommendationProvider, ListenBrainzService) {
    let keychain = RSIKeychain()
    let defaults = UserDefaults(suiteName: "test.rsi.\(UUID().uuidString)")!
    let serviceClient = ListenBrainzClient(transport: serviceTransport)
    let service = ListenBrainzService(client: serviceClient, keychain: keychain, userDefaults: defaults)
    let providerClient = ListenBrainzClient(transport: providerTransport)
    let provider = ListenBrainzRecommendationProvider(client: providerClient, service: service, libraryService: RSILibraryNullStub())
    return (provider, service)
}

// MARK: - Integration tests

@Suite("RecommendationService — integration with LB + Subsonic providers")
struct RecommendationServiceIntegrationTests {

    @Test("LB enabled: freshReleases returns LB data, Subsonic not consulted")
    func lbEnabledFreshReleasesFromLB() async throws {
        let svcTransport = RSITransport()
        svcTransport.enqueue(data: Data(#"{"payload":{"count":0}}"#.utf8), status: 200)  // enable() validation
        let provTransport = RSITransport()
        provTransport.enqueue(data: integrationJSON, status: 200)

        let (lbProvider, service) = makeLBComponents(serviceTransport: svcTransport, providerTransport: provTransport)
        try await service.enable(username: "testuser")

        let subsonicMock = RSIMockProvider()  // returns no albums — should not be reached
        let recommendationService = RecommendationService(providers: [lbProvider, subsonicMock])

        let results = try await recommendationService.freshReleases()
        #expect(results.count == 1)
        #expect(results[0].title == "LB Album")
    }

    @Test("LB disabled: freshReleases returns empty (Subsonic also returns empty, as expected)")
    func lbDisabledFreshReleasesEmpty() async throws {
        let svcTransport = RSITransport()
        let provTransport = RSITransport()
        // Service is never enabled — stays isEnabled = false
        let (lbProvider, _) = makeLBComponents(serviceTransport: svcTransport, providerTransport: provTransport)

        let subsonicMock = RSIMockProvider()  // Subsonic doesn't implement freshReleases → returns []
        let recommendationService = RecommendationService(providers: [lbProvider, subsonicMock])

        let results = try await recommendationService.freshReleases()
        #expect(results.isEmpty)
    }

    @Test("similarArtists: LB stub returns empty, first-non-empty uses Subsonic results")
    func similarArtistsFallsBackToSubsonic() async throws {
        let svcTransport = RSITransport()
        let provTransport = RSITransport()
        let (lbProvider, _) = makeLBComponents(serviceTransport: svcTransport, providerTransport: provTransport)

        let subsonicMock = RSIMockProvider(artists: [artistStubInt])
        let recommendationService = RecommendationService(providers: [lbProvider, subsonicMock])

        let results = try await recommendationService.similarArtists(to: "any-artist-id")
        #expect(results == [artistStubInt])
    }
}
