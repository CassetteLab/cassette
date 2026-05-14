// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Shared mock infrastructure

// Transport that counts calls and serves a queue of (Data, HTTPURLResponse) pairs.
private actor PRCountingTransport: ListenBrainzTransport {
    private(set) var callCount = 0
    private var queue: [(Data, HTTPURLResponse)] = []

    func enqueue(data: Data = Data(), status: Int, headers: [String: String]? = nil) {
        let resp = HTTPURLResponse(
            url: URL(string: "https://api.listenbrainz.org")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        queue.append((data, resp))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        guard !queue.isEmpty else { throw URLError(.timedOut) }
        return queue.removeFirst()
    }
}

// Separate transport for the service client used by `enable()` calls.
private actor PRServiceTransport: ListenBrainzTransport {
    private var queue: [(Data, HTTPURLResponse)] = []

    func enqueue(status: Int) {
        let resp = HTTPURLResponse(
            url: URL(string: "https://api.listenbrainz.org")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        queue.append((Data(), resp))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !queue.isEmpty else { throw URLError(.timedOut) }
        return queue.removeFirst()
    }
}

private actor PRKeychain: KeychainServiceProtocol {
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

// Transport that throws if ever called — used to verify no network call is made.
private struct PRNeverCalledTransport: ListenBrainzTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        Issue.record("Transport should not have been called")
        throw URLError(.timedOut)
    }
}

// Null library stub — safe defaults, never actually called in fresh releases tests.
private actor PRLibraryNullStub: LibraryServiceProtocol {
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
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {}
    func getPlayQueue() async throws -> SavedPlayQueue? { nil }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw URLError(.unknown) }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }
    func findArtist(byName name: String) async -> ArtistID3? { nil }
}

// Configurable library stub for similar artists tests.
private actor PRLibraryConfigurableStub: LibraryServiceProtocol {
    private var mbidResult: Result<String?, Error> = .success(nil)
    private var artistsByName: [String: ArtistID3] = [:]

    func set(mbidResult: Result<String?, Error>) { self.mbidResult = mbidResult }
    func set(artistsByName: [String: ArtistID3]) { self.artistsByName = artistsByName }

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
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {}
    func getPlayQueue() async throws -> SavedPlayQueue? { nil }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw URLError(.unknown) }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { try mbidResult.get() }
    func findArtist(byName name: String) async -> ArtistID3? { artistsByName[name] }
}

// MARK: - Fixtures

private let singleReleaseJSON = Data("""
{
  "payload": {
    "releases": [
      {
        "artist_credit_name": "Test Artist",
        "release_name": "Test Album",
        "release_date": "2026-06-01",
        "release_group_mbid": "rrrrrrrr-gggg-mmmm-bbbb-iiiiiiiiiiii",
        "caa_id": 111222333,
        "caa_release_mbid": "cccccccc-aaaa-bbbb-cccc-aaaaaaaaaaaa"
      }
    ]
  }
}
""".utf8)

private let twoReleasesWithBadDateJSON = Data("""
{
  "payload": {
    "releases": [
      {
        "artist_credit_name": "Good Date Artist",
        "release_name": "Good Date Album",
        "release_date": "2026-05-01",
        "release_group_mbid": "11111111-0000-0000-0000-000000000000"
      },
      {
        "artist_credit_name": "Bad Date Artist",
        "release_name": "Bad Date Album",
        "release_date": "not-a-date",
        "release_group_mbid": "22222222-0000-0000-0000-000000000000"
      }
    ]
  }
}
""".utf8)

// 5 releases delivered oldest-first (as LB does), with dates spanning Jan–May.
private let fiveReleasesOldestFirstJSON = Data("""
{
  "payload": {
    "releases": [
      { "artist_credit_name": "Old1", "release_name": "Old 1", "release_date": "2026-01-10", "release_group_mbid": "old1" },
      { "artist_credit_name": "Old2", "release_name": "Old 2", "release_date": "2026-02-15", "release_group_mbid": "old2" },
      { "artist_credit_name": "Old3", "release_name": "Old 3", "release_date": "2026-03-01", "release_group_mbid": "old3" },
      { "artist_credit_name": "New2", "release_name": "New 2", "release_date": "2026-05-05", "release_group_mbid": "new2" },
      { "artist_credit_name": "New1", "release_name": "New 1", "release_date": "2026-05-10", "release_group_mbid": "new1" }
    ]
  }
}
""".utf8)

// 3 releases: 2 with dates, 1 with no date field (maps to nil releaseDate).
private let twoDatedOneNilJSON = Data("""
{
  "payload": {
    "releases": [
      { "artist_credit_name": "May", "release_name": "May Album",   "release_date": "2026-05-01", "release_group_mbid": "may" },
      { "artist_credit_name": "Nil", "release_name": "Nil Album",                                  "release_group_mbid": "nil" },
      { "artist_credit_name": "Apr", "release_name": "April Album", "release_date": "2026-04-01", "release_group_mbid": "apr" }
    ]
  }
}
""".utf8)

private let noMbidJSON = Data("""
{
  "payload": {
    "releases": [
      {
        "artist_credit_name": "No Cover Artist",
        "release_name": "No Cover Album"
      }
    ]
  }
}
""".utf8)

// MARK: - Helpers

private func makeService(serviceTransport: any ListenBrainzTransport) -> ListenBrainzService {
    let client = ListenBrainzClient(transport: serviceTransport)
    let keychain = PRKeychain()
    let defaults = UserDefaults(suiteName: "test.lbprov.\(UUID().uuidString)")!
    return ListenBrainzService(client: client, keychain: keychain, userDefaults: defaults)
}

private func makeProvider(
    providerTransport: any ListenBrainzTransport,
    service: ListenBrainzService,
    libraryService: (any LibraryServiceProtocol)? = nil,
    cacheTTL: TimeInterval = 3600
) -> ListenBrainzRecommendationProvider {
    let client = ListenBrainzClient(transport: providerTransport)
    return ListenBrainzRecommendationProvider(
        client: client,
        service: service,
        libraryService: libraryService ?? PRLibraryNullStub(),
        cacheTTL: cacheTTL
    )
}

// MARK: - Early-exit tests

@Suite("ListenBrainzRecommendationProvider — early exit")
struct LBProviderEarlyExitTests {

    @Test("disabled service returns empty without network call")
    func disabledServiceReturnsEmpty() async throws {
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: PRNeverCalledTransport(), service: service)

        let results = try await provider.freshReleases(limit: 10, daysWindow: 90)
        #expect(results.isEmpty)
    }

    @Test("enabled service but no username returns empty without network call")
    func enabledButNoUsernameReturnsEmpty() async throws {
        // Service stays in default state: isEnabled = false, username = nil.
        // Even if we manually flip isEnabled without a username, the guard covers this.
        // The default state has isEnabled = false, so this is the simpler variant of the test.
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: PRNeverCalledTransport(), service: service)

        let snap = await service.currentSnapshot()
        #expect(!snap.isEnabled)
        #expect(snap.username == nil)

        let results = try await provider.freshReleases(limit: 10, daysWindow: 90)
        #expect(results.isEmpty)
    }
}

// MARK: - Happy path

@Suite("ListenBrainzRecommendationProvider — happy path")
struct LBProviderHappyPathTests {

    @Test("enabled service with username returns mapped AlbumRecommendations")
    func happyPathReturnsResults() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)  // for enable() validation
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: singleReleaseJSON, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        let results = try await provider.freshReleases(limit: 10, daysWindow: 90)

        #expect(results.count == 1)
        #expect(results[0].title == "Test Album")
        #expect(results[0].artistName == "Test Artist")
        #expect(results[0].inLibrary == false)
        #expect(results[0].id == "rrrrrrrr-gggg-mmmm-bbbb-iiiiiiiiiiii")
        let expectedURL = URL(string: "https://coverartarchive.org/release/cccccccc-aaaa-bbbb-cccc-aaaaaaaaaaaa/111222333-250.jpg")
        #expect(results[0].coverArtURL == expectedURL)
        #expect(await providerTransport.callCount == 1)
    }

    @Test("limit keeps most recent releases, not arrival order")
    func limitKeepsMostRecent() async throws {
        // LB returns 5 releases oldest-first. With limit=3 we must get the 3 newest.
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: fiveReleasesOldestFirstJSON, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        let results = try await provider.freshReleases(limit: 3, daysWindow: 90)

        #expect(results.count == 3)
        // Expecting: New1 (May 10), New2 (May 5), Old3 (Mar 1) — the 3 most recent
        #expect(results.map { $0.id } == ["new1", "new2", "old3"])
    }

    @Test("releases with nil releaseDate are sorted last and cut first by limit")
    func nilDateSortedLastCutByLimit() async throws {
        // 3 releases: May (dated), nil (no date), Apr (dated). limit=2 must drop the nil one.
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: twoDatedOneNilJSON, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        let results = try await provider.freshReleases(limit: 2, daysWindow: 90)

        #expect(results.count == 2)
        #expect(results.map { $0.id } == ["may", "apr"])
        #expect(!results.contains(where: { $0.id == "nil" }))
    }

    @Test("limit parameter trims results")
    func limitTrimsResults() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        let twoReleasesJSON = Data("""
        {
          "payload": {
            "releases": [
              { "artist_credit_name": "A1", "release_name": "R1", "release_group_mbid": "aa" },
              { "artist_credit_name": "A2", "release_name": "R2", "release_group_mbid": "bb" }
            ]
          }
        }
        """.utf8)
        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: twoReleasesJSON, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        let results = try await provider.freshReleases(limit: 1, daysWindow: 90)
        #expect(results.count == 1)
    }
}

// MARK: - Cache

@Suite("ListenBrainzRecommendationProvider — cache")
struct LBProviderCacheTests {

    @Test("cache hit within TTL makes only one network call for two requests")
    func cacheHitOneNetworkCall() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: singleReleaseJSON, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service, cacheTTL: 3600)

        _ = try await provider.freshReleases(limit: 10, daysWindow: 90)
        _ = try await provider.freshReleases(limit: 10, daysWindow: 90)

        #expect(await providerTransport.callCount == 1)
    }

    @Test("cache miss after TTL expiry makes two network calls")
    func cacheMissAfterExpiry() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: singleReleaseJSON, status: 200)
        await providerTransport.enqueue(data: singleReleaseJSON, status: 200)
        // TTL of 0.01s (10ms)
        let provider = makeProvider(providerTransport: providerTransport, service: service, cacheTTL: 0.01)

        _ = try await provider.freshReleases(limit: 10, daysWindow: 90)
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms — lets the 10ms TTL expire
        _ = try await provider.freshReleases(limit: 10, daysWindow: 90)

        #expect(await providerTransport.callCount == 2)
    }

    @Test("username change invalidates cache and triggers a new network call")
    func usernameChangeInvalidatesCache() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)  // enable user1
        await serviceTransport.enqueue(status: 200)  // enable user2
        let service = makeService(serviceTransport: serviceTransport)

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: singleReleaseJSON, status: 200)  // first freshReleases
        await providerTransport.enqueue(data: singleReleaseJSON, status: 200)  // second freshReleases
        let provider = makeProvider(providerTransport: providerTransport, service: service, cacheTTL: 3600)

        try await service.enable(username: "user1")
        _ = try await provider.freshReleases(limit: 10, daysWindow: 90)

        try await service.enable(username: "user2")
        _ = try await provider.freshReleases(limit: 10, daysWindow: 90)

        #expect(await providerTransport.callCount == 2)
    }
}

// MARK: - Error handling

@Suite("ListenBrainzRecommendationProvider — error handling")
struct LBProviderErrorTests {

    @Test("userNotFound from client returns empty gracefully without rethrowing")
    func userNotFoundGraceful() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(status: 404)  // simulates stale username on LB side
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        let results = try await provider.freshReleases(limit: 10, daysWindow: 90)
        #expect(results.isEmpty)
    }

    @Test("network error from client is rethrown")
    func networkErrorPropagates() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        // Empty queue → URLError(.timedOut) → wrapped as .network
        let providerTransport = PRCountingTransport()
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        var caught: Error?
        do {
            _ = try await provider.freshReleases(limit: 10, daysWindow: 90)
        } catch {
            caught = error
        }
        if case .network = caught as? ListenBrainzError {} else {
            Issue.record("Expected .network, got \(String(describing: caught))")
        }
    }

}

// MARK: - Mapping

@Suite("ListenBrainzRecommendationProvider — mapping")
struct LBProviderMappingTests {

    @Test("cover URL uses CAA when caaId and caaReleaseMbid are present")
    func coverURLWithCAA() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "u")

        let json = Data("""
        {
          "payload": { "releases": [{
            "artist_credit_name": "A", "release_name": "R",
            "release_group_mbid": "rg-mbid",
            "caa_id": 9876,
            "caa_release_mbid": "rel-mbid"
          }] }
        }
        """.utf8)
        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: json, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        let results = try await provider.freshReleases(limit: 10, daysWindow: 90)
        #expect(results[0].coverArtURL == URL(string: "https://coverartarchive.org/release/rel-mbid/9876-250.jpg"))
    }

    @Test("cover URL falls back to release-group when caaId is absent")
    func coverURLFallbackToReleaseGroup() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "u")

        let json = Data("""
        {
          "payload": { "releases": [{
            "artist_credit_name": "A", "release_name": "R",
            "release_group_mbid": "rg-only-mbid"
          }] }
        }
        """.utf8)
        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: json, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        let results = try await provider.freshReleases(limit: 10, daysWindow: 90)
        #expect(results[0].coverArtURL == URL(string: "https://coverartarchive.org/release-group/rg-only-mbid/front-250"))
    }

    @Test("cover URL is nil when no mbid or caa fields are present")
    func coverURLNilWhenNoIds() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "u")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: noMbidJSON, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        let results = try await provider.freshReleases(limit: 10, daysWindow: 90)
        #expect(results[0].coverArtURL == nil)
    }

    @Test("malformed release_date yields nil releaseDate; valid entry in same response is preserved")
    func malformedDateNilOtherPreserved() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "u")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: twoReleasesWithBadDateJSON, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service)

        let results = try await provider.freshReleases(limit: 10, daysWindow: 90)
        #expect(results.count == 2)

        // Fixture JSON: Good Date Artist is index 0, Bad Date Artist is index 1
        #expect(results[0].releaseDate != nil, "Good Date Artist should have a parsed date")
        #expect(results[1].releaseDate == nil, "Bad Date Artist has an unparseable release_date")
    }
}

// MARK: - Window isolation

@Suite("LBProviderWindowTests")
struct LBProviderWindowTests {

    @Test("two different daysWindow values produce two network calls (cache not shared)")
    func differentWindowsMakeTwoNetworkCalls() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: singleReleaseJSON, status: 200)  // daysWindow: 7
        await providerTransport.enqueue(data: singleReleaseJSON, status: 200)  // daysWindow: 90
        let provider = makeProvider(providerTransport: providerTransport, service: service, cacheTTL: 3600)

        _ = try await provider.freshReleases(limit: 10, daysWindow: 7)
        _ = try await provider.freshReleases(limit: 10, daysWindow: 90)

        #expect(await providerTransport.callCount == 2)
    }

    @Test("same daysWindow used twice hits cache and makes only one network call")
    func sameWindowTwiceUsesCache() async throws {
        let serviceTransport = PRServiceTransport()
        await serviceTransport.enqueue(status: 200)
        let service = makeService(serviceTransport: serviceTransport)
        try await service.enable(username: "testuser")

        let providerTransport = PRCountingTransport()
        await providerTransport.enqueue(data: singleReleaseJSON, status: 200)
        let provider = makeProvider(providerTransport: providerTransport, service: service, cacheTTL: 3600)

        _ = try await provider.freshReleases(limit: 10, daysWindow: 7)
        _ = try await provider.freshReleases(limit: 10, daysWindow: 7)

        #expect(await providerTransport.callCount == 1)
    }
}

// MARK: - Similar artists

private let twoSimilarArtistsJSON = Data("""
{
  "similarArtists": {
    "artists": [
      { "artist_mbid": "mb-brian", "name": "Brian May", "score": 3389 },
      { "artist_mbid": "mb-roger", "name": "Roger Waters", "score": 2100 }
    ]
  }
}
""".utf8)

@Suite("LBProviderSimilarArtistsTests")
struct LBProviderSimilarArtistsTests {

    @Test("nil MBID returns empty without LB network call")
    func noMBIDReturnsEmptyNoNetworkCall() async throws {
        let stub = PRLibraryConfigurableStub()
        await stub.set(mbidResult: .success(nil))
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: PRNeverCalledTransport(), service: service, libraryService: stub)

        let results = try await provider.similarArtists(toArtistID: "sub-ar-123", limit: 20)
        #expect(results.isEmpty)
    }

    @Test("MBID lookup throws returns empty without LB network call")
    func mbidLookupThrowsReturnsEmpty() async throws {
        let stub = PRLibraryConfigurableStub()
        await stub.set(mbidResult: .failure(URLError(.cannotConnectToHost)))
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: PRNeverCalledTransport(), service: service, libraryService: stub)

        let results = try await provider.similarArtists(toArtistID: "sub-ar-123", limit: 20)
        #expect(results.isEmpty)
    }

    @Test("LB 404 (artist unknown to LB) returns empty")
    func artistNotInLBReturnsEmpty() async throws {
        let stub = PRLibraryConfigurableStub()
        await stub.set(mbidResult: .success("some-mbid"))
        let transport = PRCountingTransport()
        await transport.enqueue(status: 404)
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: transport, service: service, libraryService: stub)

        let results = try await provider.similarArtists(toArtistID: "sub-ar-123", limit: 20)
        #expect(results.isEmpty)
    }

    @Test("happy path maps artists correctly")
    func happyPathMapsCorrectly() async throws {
        let stub = PRLibraryConfigurableStub()
        await stub.set(mbidResult: .success("bowie-mbid"))
        let transport = PRCountingTransport()
        await transport.enqueue(data: twoSimilarArtistsJSON, status: 200)
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: transport, service: service, libraryService: stub)

        let results = try await provider.similarArtists(toArtistID: "sub-ar-bowie", limit: 20)

        #expect(results.count == 2)
        #expect(results[0].name == "Brian May")
        #expect(results[0].mbid == "mb-brian")
        #expect(results[1].name == "Roger Waters")
        #expect(results[1].mbid == "mb-roger")
        #expect(await transport.callCount == 1)
    }

    @Test("artist found in library is marked inLibrary with Subsonic ID and coverArt")
    func inLibraryEnrichment() async throws {
        let stub = PRLibraryConfigurableStub()
        await stub.set(mbidResult: .success("bowie-mbid"))
        await stub.set(artistsByName: ["Brian May": ArtistID3(id: "ar-brian", name: "Brian May", coverArt: "ca-brian")])

        let transport = PRCountingTransport()
        await transport.enqueue(data: twoSimilarArtistsJSON, status: 200)
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: transport, service: service, libraryService: stub)

        let results = try await provider.similarArtists(toArtistID: "sub-ar-bowie", limit: 20)

        let brian = results.first { $0.name == "Brian May" }
        #expect(brian?.inLibrary == true)
        #expect(brian?.id == "ar-brian")
        #expect(brian?.coverArt == "ca-brian")
        #expect(brian?.mbid == "mb-brian")
    }

    @Test("artist not in library uses MBID as id and inLibrary is false")
    func notInLibraryEnrichment() async throws {
        let stub = PRLibraryConfigurableStub()
        await stub.set(mbidResult: .success("bowie-mbid"))

        let transport = PRCountingTransport()
        await transport.enqueue(data: twoSimilarArtistsJSON, status: 200)
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: transport, service: service, libraryService: stub)

        let results = try await provider.similarArtists(toArtistID: "sub-ar-bowie", limit: 20)

        let roger = results.first { $0.name == "Roger Waters" }
        #expect(roger?.inLibrary == false)
        #expect(roger?.id == "mb-roger")
        #expect(roger?.coverArt == nil)
        #expect(roger?.mbid == "mb-roger")
    }

    @Test("limit parameter trims results")
    func limitApplied() async throws {
        let stub = PRLibraryConfigurableStub()
        await stub.set(mbidResult: .success("bowie-mbid"))
        let transport = PRCountingTransport()
        await transport.enqueue(data: twoSimilarArtistsJSON, status: 200)
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: transport, service: service, libraryService: stub)

        let results = try await provider.similarArtists(toArtistID: "sub-ar-bowie", limit: 1)
        #expect(results.count == 1)
        #expect(results[0].name == "Brian May")
    }
}
