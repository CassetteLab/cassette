// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Response fixtures

private let testMBID = "5b11f4ce-a62d-471e-81fc-a69a8278c7da"
private let testQID  = "Q392"

private func mbSearchResponse(artists: [(id: String, name: String, score: Int)]) -> Data {
    let body = artists.map { #"{"id":"\#($0.id)","name":"\#($0.name)","score":\#($0.score)}"# }.joined(separator: ",")
    return Data(#"{"artists":[\#(body)]}"#.utf8)
}

private let mbSearchEmpty = Data(#"{"artists":[]}"#.utf8)

private func mbArtistResponse(withWikidata qid: String) -> Data {
    Data("""
    {"relations":[{"type":"wikidata","url":{"resource":"https://www.wikidata.org/wiki/\(qid)"}}]}
    """.utf8)
}

private let mbArtistNoWikidata = Data(#"{"relations":[]}"#.utf8)

private func wdResponse(qid: String, filename: String) -> Data {
    Data("""
    {"entities":{"\(qid)":{"claims":{"P18":[{"mainsnak":{"datavalue":{"value":"\(filename)"}}}]}}}}
    """.utf8)
}

// MARK: - Stub HTTP client

private actor StubHTTPClient: ArtistImageHTTPClient {
    typealias Handler = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private(set) var callCount = 0
    private var handlers: [Handler]
    private var index = 0

    init(responses: [Handler]) { handlers = responses }

    nonisolated func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await _data(for: request)
    }

    private func _data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        let i = min(index, handlers.count - 1)
        index += 1
        return try await handlers[i](request)
    }
}

private func ok(_ data: Data) -> StubHTTPClient.Handler {
    { req in (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
}

private func fail(_ error: Error) -> StubHTTPClient.Handler {
    { _ in throw error }
}

// MARK: - Tests

@Suite("ExternalArtistImageResolver")
struct ExternalArtistImageResolverTests {

    // MARK: MBID-based pipeline

    @Test("MBID happy path returns Commons URL")
    func mbidHappyPath() async {
        let client = StubHTTPClient(responses: [
            ok(mbArtistResponse(withWikidata: testQID)),
            ok(wdResponse(qid: testQID, filename: "Test_Artist.jpg"))
        ])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url = await resolver.resolveImageURL(forArtistMBID: testMBID)

        #expect(url?.absoluteString.contains("Special:FilePath/Test_Artist.jpg") == true)
        #expect(url?.absoluteString.contains("width=500") == true)
        let count = await client.callCount
        #expect(count == 2)
    }

    @Test("No Wikidata relation returns nil")
    func noWikidataRelation() async {
        let client = StubHTTPClient(responses: [ok(mbArtistNoWikidata)])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url = await resolver.resolveImageURL(forArtistMBID: testMBID)
        #expect(url == nil)
    }

    @Test("No P18 claim returns nil")
    func noP18() async {
        let wdNoP18 = Data(#"{"entities":{"\#(testQID)":{"claims":{}}}}"#.utf8)
        let client = StubHTTPClient(responses: [
            ok(mbArtistResponse(withWikidata: testQID)),
            ok(wdNoP18)
        ])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url = await resolver.resolveImageURL(forArtistMBID: testMBID)
        #expect(url == nil)
    }

    @Test("MBID cache hit makes no additional network calls")
    func mbidCacheHit() async {
        let client = StubHTTPClient(responses: [
            ok(mbArtistResponse(withWikidata: testQID)),
            ok(wdResponse(qid: testQID, filename: "Artist.jpg"))
        ])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url1 = await resolver.resolveImageURL(forArtistMBID: testMBID)
        let url2 = await resolver.resolveImageURL(forArtistMBID: testMBID)

        #expect(url1 == url2)
        let count = await client.callCount
        #expect(count == 2)
    }

    @Test("Concurrent MBID requests share one Task")
    func mbidInflightDedup() async {
        let client = StubHTTPClient(responses: [ok(mbArtistNoWikidata)])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        async let r1 = resolver.resolveImageURL(forArtistMBID: testMBID)
        async let r2 = resolver.resolveImageURL(forArtistMBID: testMBID)
        async let r3 = resolver.resolveImageURL(forArtistMBID: testMBID)

        let (u1, u2, u3) = await (r1, r2, r3)
        #expect(u1 == u2 && u2 == u3)
        let count = await client.callCount
        #expect(count == 1)
    }

    @Test("Network error returns nil gracefully")
    func networkError() async {
        struct FakeError: Error {}
        let client = StubHTTPClient(responses: [fail(FakeError())])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url = await resolver.resolveImageURL(forArtistMBID: testMBID)
        #expect(url == nil)
    }

    @Test("Sequential MBID calls respect the 1-second rate limit")
    func rateLimitEnforced() async {
        let client = StubHTTPClient(responses: [ok(mbArtistNoWikidata), ok(mbArtistNoWikidata)])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let t0 = Date()
        _ = await resolver.resolveImageURL(forArtistMBID: testMBID)
        _ = await resolver.resolveImageURL(forArtistMBID: "another-mbid")

        #expect(Date().timeIntervalSince(t0) >= 1.0)
    }

    // MARK: Name-based search

    @Test("Name search happy path returns Commons URL")
    func nameHappyPath() async {
        let client = StubHTTPClient(responses: [
            ok(mbSearchResponse(artists: [(id: testMBID, name: "Test Artist", score: 100)])),
            ok(mbArtistResponse(withWikidata: testQID)),
            ok(wdResponse(qid: testQID, filename: "Test_Artist.jpg"))
        ])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url = await resolver.resolveImageURL(forArtistName: "Test Artist")

        #expect(url?.absoluteString.contains("Special:FilePath") == true)
        let count = await client.callCount
        #expect(count == 3)
    }

    @Test("Name search low score returns nil without proceeding to pipeline")
    func nameSearchLowScore() async {
        let client = StubHTTPClient(responses: [
            ok(mbSearchResponse(artists: [(id: testMBID, name: "Someone Else", score: 50)]))
        ])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url = await resolver.resolveImageURL(forArtistName: "Unknown Artist XYZ123")

        #expect(url == nil)
        let count = await client.callCount
        #expect(count == 1)
    }

    @Test("Name exact match at score 80 is accepted (proceeds to pipeline)")
    func nameExactMatchScore80() async {
        let client = StubHTTPClient(responses: [
            ok(mbSearchResponse(artists: [(id: testMBID, name: "Test Artist", score: 83)])),
            ok(mbArtistNoWikidata)
        ])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        _ = await resolver.resolveImageURL(forArtistName: "Test Artist")

        // Score 83 with exact name match → pipeline proceeds → MB artist call happens
        let count = await client.callCount
        #expect(count == 2)
    }

    @Test("Name cache hit makes no additional network calls")
    func nameCacheHit() async {
        let client = StubHTTPClient(responses: [
            ok(mbSearchResponse(artists: [(id: testMBID, name: "Test Artist", score: 100)])),
            ok(mbArtistNoWikidata)
        ])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url1 = await resolver.resolveImageURL(forArtistName: "Test Artist")
        let url2 = await resolver.resolveImageURL(forArtistName: "Test Artist")

        #expect(url1 == url2)
        let count = await client.callCount
        #expect(count == 2)
    }

    @Test("Concurrent name requests share one Task")
    func nameInflightDedup() async {
        // Use low-score response: pipeline stops after search (1 call, no rate-limit delay)
        let client = StubHTTPClient(responses: [
            ok(mbSearchResponse(artists: [(id: testMBID, name: "Other", score: 30)]))
        ])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        async let r1 = resolver.resolveImageURL(forArtistName: "Test Artist")
        async let r2 = resolver.resolveImageURL(forArtistName: "Test Artist")
        async let r3 = resolver.resolveImageURL(forArtistName: "Test Artist")
        async let r4 = resolver.resolveImageURL(forArtistName: "Test Artist")
        async let r5 = resolver.resolveImageURL(forArtistName: "Test Artist")

        let results = await [r1, r2, r3, r4, r5]
        #expect(results.allSatisfy { $0 == nil })
        let count = await client.callCount
        #expect(count == 1)
    }

    // MARK: MBID guard

    @Test("Empty MBID returns nil without network call")
    func emptyMBIDGuard() async {
        let client = StubHTTPClient(responses: [])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url = await resolver.resolveImageURL(forArtistMBID: "")

        #expect(url == nil)
        let count = await client.callCount
        #expect(count == 0)
    }

    @Test("Whitespace MBID returns nil without network call")
    func whitespaceMBIDGuard() async {
        let client = StubHTTPClient(responses: [])
        let resolver = ExternalArtistImageResolver(httpClient: client)

        let url = await resolver.resolveImageURL(forArtistMBID: "   ")

        #expect(url == nil)
        let count = await client.callCount
        #expect(count == 0)
    }
}
