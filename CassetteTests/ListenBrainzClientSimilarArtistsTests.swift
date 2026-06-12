// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Fixtures

private let validSimilarArtistsJSON = Data("""
{
  "similarArtists": {
    "artists": [
      { "artist_mbid": "mb-brian", "name": "Brian May",    "score": 3389 },
      { "artist_mbid": "mb-iggy",  "name": "Iggy Pop",     "score": 2100 }
    ]
  }
}
""".utf8)

private let malformedEntryJSON = Data("""
{
  "similarArtists": {
    "artists": [
      { "name": "Missing MBID", "score": 999 },
      { "artist_mbid": "mb-valid", "name": "Valid Artist", "score": 50 }
    ]
  }
}
""".utf8)

// MARK: - Transports

@MainActor
private final class CLCountingTransport: ListenBrainzTransport {
    private(set) var callCount = 0
    private(set) var lastRequest: URLRequest?
    private var queue: [(Data, HTTPURLResponse)] = []

    func enqueue(data: Data = Data(), status: Int) {
        let resp = HTTPURLResponse(
            url: URL(string: "https://listenbrainz.org")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        queue.append((data, resp))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        lastRequest = request
        guard !queue.isEmpty else { throw URLError(.timedOut) }
        return queue.removeFirst()
    }
}

// MARK: - Tests

@Suite("ListenBrainzClient — similarArtists")
struct ListenBrainzClientSimilarArtistsTests {

    @Test("200 response with valid JSON returns parsed artist list")
    func happyPathReturnsParsedArtists() async throws {
        let transport = CLCountingTransport()
        transport.enqueue(data: validSimilarArtistsJSON, status: 200)
        let client = ListenBrainzClient(transport: transport)

        let artists = try await client.similarArtists(mbid: "bowie-mbid")

        #expect(artists.count == 2)
        #expect(artists[0].name == "Brian May")
        #expect(artists[0].artistMbid == "mb-brian")
        #expect(artists[0].score == 3389)
        #expect(artists[1].name == "Iggy Pop")
        #expect(transport.callCount == 1)
    }

    @Test("404 returns empty array without throwing")
    func notFoundReturnsEmpty() async throws {
        let transport = CLCountingTransport()
        transport.enqueue(status: 404)
        let client = ListenBrainzClient(transport: transport)

        let artists = try await client.similarArtists(mbid: "unknown-mbid")
        #expect(artists.isEmpty)
    }

    @Test("429 throws rateLimited error")
    func rateLimitedThrows() async throws {
        let transport = CLCountingTransport()
        transport.enqueue(status: 429)
        let client = ListenBrainzClient(transport: transport)

        var caught: Error?
        do {
            _ = try await client.similarArtists(mbid: "some-mbid")
        } catch {
            caught = error
        }
        if case .rateLimited = caught as? ListenBrainzError {} else {
            Issue.record("Expected .rateLimited, got \(String(describing: caught))")
        }
    }

    @Test("500 throws httpError")
    func serverErrorThrows() async throws {
        let transport = CLCountingTransport()
        transport.enqueue(status: 500)
        let client = ListenBrainzClient(transport: transport)

        var caught: Error?
        do {
            _ = try await client.similarArtists(mbid: "some-mbid")
        } catch {
            caught = error
        }
        if case .httpError(500) = caught as? ListenBrainzError {} else {
            Issue.record("Expected .httpError(500), got \(String(describing: caught))")
        }
    }

    @Test("malformed entry in array is silently skipped; valid sibling preserved")
    func malformedEntrySkippedValidPreserved() async throws {
        let transport = CLCountingTransport()
        transport.enqueue(data: malformedEntryJSON, status: 200)
        let client = ListenBrainzClient(transport: transport)

        let artists = try await client.similarArtists(mbid: "some-mbid")

        #expect(artists.count == 1)
        #expect(artists[0].name == "Valid Artist")
        #expect(artists[0].artistMbid == "mb-valid")
    }

    @Test("request is sent to listenbrainz.org with correct MBID in path")
    func requestSentToCorrectHost() async throws {
        let mbid = "5441c29d-3602-4898-b1a1-b77fa23b8e50"
        let transport = CLCountingTransport()
        transport.enqueue(data: validSimilarArtistsJSON, status: 200)
        let client = ListenBrainzClient(transport: transport)

        _ = try await client.similarArtists(mbid: mbid)

        let req = transport.lastRequest
        let urlString = req?.url?.absoluteString ?? ""
        #expect(urlString.contains("listenbrainz.org"))
        #expect(urlString.contains(mbid))
    }
}
