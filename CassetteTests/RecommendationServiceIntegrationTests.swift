// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Integration mock infrastructure

private actor RSITransport: ListenBrainzTransport {
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

private actor RSIKeychain: KeychainServiceProtocol {
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

    func freshReleases(limit: Int) async throws -> [AlbumRecommendation] { albumResults }
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

private let artistStubInt = SimilarArtistRecommendation(id: "sub-a1", name: "Subsonic Artist", coverArt: nil, inLibrary: true)

private func makeLBComponents(serviceTransport: any ListenBrainzTransport, providerTransport: any ListenBrainzTransport) -> (ListenBrainzRecommendationProvider, ListenBrainzService) {
    let keychain = RSIKeychain()
    let defaults = UserDefaults(suiteName: "test.rsi.\(UUID().uuidString)")!
    let serviceClient = ListenBrainzClient(transport: serviceTransport)
    let service = ListenBrainzService(client: serviceClient, keychain: keychain, userDefaults: defaults)
    let providerClient = ListenBrainzClient(transport: providerTransport)
    let provider = ListenBrainzRecommendationProvider(client: providerClient, service: service)
    return (provider, service)
}

// MARK: - Integration tests

@Suite("RecommendationService — integration with LB + Subsonic providers")
struct RecommendationServiceIntegrationTests {

    @Test("LB enabled: freshReleases returns LB data, Subsonic not consulted")
    func lbEnabledFreshReleasesFromLB() async throws {
        let svcTransport = RSITransport()
        await svcTransport.enqueue(status: 200)  // enable() validation
        let provTransport = RSITransport()
        await provTransport.enqueue(data: integrationJSON, status: 200)

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
