// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Mock

private enum MockError: Error { case failure }

private struct MockRecommendationProvider: RecommendationProvider {
    let artistResults: [SimilarArtistRecommendation]
    let albumResults: [AlbumRecommendation]
    let shouldThrow: Bool

    init(
        artistResults: [SimilarArtistRecommendation] = [],
        albumResults: [AlbumRecommendation] = [],
        shouldThrow: Bool = false
    ) {
        self.artistResults = artistResults
        self.albumResults = albumResults
        self.shouldThrow = shouldThrow
    }

    func similarArtists(toArtistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] {
        if shouldThrow { throw MockError.failure }
        return artistResults
    }

    func freshReleases(limit: Int) async throws -> [AlbumRecommendation] {
        if shouldThrow { throw MockError.failure }
        return albumResults
    }
}

// MARK: - Fixtures

private let artistStub = SimilarArtistRecommendation(id: "a1", name: "Artist One", coverArt: nil, inLibrary: true, mbid: nil)
private let artistStub2 = SimilarArtistRecommendation(id: "a2", name: "Artist Two", coverArt: nil, inLibrary: true, mbid: nil)
private let albumStub = AlbumRecommendation(id: "al1", title: "Album One", artistName: "Artist One", releaseDate: nil, coverArtURL: nil, inLibrary: true)

// MARK: - RecommendationService — similarArtists

@Suite("RecommendationService — similarArtists")
struct RecommendationServiceSimilarArtistsTests {

    @Test("single provider with results returns them")
    func singleProviderReturnsData() async throws {
        let service = RecommendationService(providers: [MockRecommendationProvider(artistResults: [artistStub])])
        let results = try await service.similarArtists(to: "a1")
        #expect(results == [artistStub])
    }

    @Test("single provider returning empty yields empty")
    func singleProviderReturnsEmpty() async throws {
        let service = RecommendationService(providers: [MockRecommendationProvider()])
        let results = try await service.similarArtists(to: "a1")
        #expect(results.isEmpty)
    }

    @Test("first non-empty provider wins over later non-empty provider")
    func firstProviderWinsWhenBothHaveData() async throws {
        let first = MockRecommendationProvider(artistResults: [artistStub])
        let second = MockRecommendationProvider(artistResults: [artistStub2])
        let service = RecommendationService(providers: [first, second])
        let results = try await service.similarArtists(to: "x")
        #expect(results == [artistStub])
    }

    @Test("second provider used when first returns empty")
    func secondProviderFallback() async throws {
        let first = MockRecommendationProvider()
        let second = MockRecommendationProvider(artistResults: [artistStub])
        let service = RecommendationService(providers: [first, second])
        let results = try await service.similarArtists(to: "x")
        #expect(results == [artistStub])
    }

    @Test("throwing provider propagates error")
    func throwingProviderPropagates() async {
        let service = RecommendationService(providers: [MockRecommendationProvider(shouldThrow: true)])
        var caughtError: Error?
        do {
            _ = try await service.similarArtists(to: "x")
        } catch {
            caughtError = error
        }
        #expect(caughtError is MockError)
    }
}

// MARK: - RecommendationService — freshReleases

@Suite("RecommendationService — freshReleases")
struct RecommendationServiceFreshReleasesTests {

    @Test("empty provider yields empty")
    func emptyProviderReturnsEmpty() async throws {
        let service = RecommendationService(providers: [MockRecommendationProvider()])
        let results = try await service.freshReleases()
        #expect(results.isEmpty)
    }

    @Test("provider with albums returns them")
    func providerWithAlbumsReturnsData() async throws {
        let service = RecommendationService(providers: [MockRecommendationProvider(albumResults: [albumStub])])
        let results = try await service.freshReleases()
        #expect(results == [albumStub])
    }

    @Test("throwing provider propagates error")
    func throwingProviderPropagates() async {
        let service = RecommendationService(providers: [MockRecommendationProvider(shouldThrow: true)])
        var caughtError: Error?
        do {
            _ = try await service.freshReleases()
        } catch {
            caughtError = error
        }
        #expect(caughtError is MockError)
    }
}
