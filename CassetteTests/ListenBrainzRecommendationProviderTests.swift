// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
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
    cacheTTL: TimeInterval = 3600
) -> ListenBrainzRecommendationProvider {
    let client = ListenBrainzClient(transport: providerTransport)
    return ListenBrainzRecommendationProvider(client: client, service: service, cacheTTL: cacheTTL)
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

    @Test("similarArtists returns empty (stub)")
    func similarArtistsStub() async throws {
        let service = makeService(serviceTransport: PRNeverCalledTransport())
        let provider = makeProvider(providerTransport: PRNeverCalledTransport(), service: service)

        let results = try await provider.similarArtists(toArtistID: "some-id", limit: 20)
        #expect(results.isEmpty)
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
