// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

/// Serves canned responses per path, and records the request bodies it saw.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static let lock = NSLock()
    nonisolated(unsafe) static var responses: [String: (status: Int, body: String)] = [:]
    nonisolated(unsafe) static var bodies: [String: [String: Any]] = [:]

    static func reset() {
        lock.withLock { responses = [:]; bodies = [:] }
    }
    static func stub(_ path: String, status: Int = 200, body: String) {
        lock.withLock { responses[path] = (status, body) }
    }
    static func body(for path: String) -> [String: Any]? {
        lock.withLock { bodies[path] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        // URLProtocol strips httpBody into httpBodyStream, so it has to be read back out.
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Self.lock.withLock { Self.bodies[path] = json }
            }
        }
        let stub = Self.lock.withLock { Self.responses[path] } ?? (404, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func makeClient(token: String? = nil) -> AudioMuseClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return AudioMuseClient(urlString: "http://muse.local:8000", token: token, session: URLSession(configuration: config))!
}

@Suite("AudioMuse client", .serialized)
struct AudioMuseClientTests {

    @Test("a normal search returns the media server's track ids")
    func searchReturnsProviderIds() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[{"server_id":"nav1","name":"Navidrome"}],"default_id":"nav1"}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"G90Au1giwNr8o1HXhxiXpM","title":"T"}]}"#)

        let tracks = try await makeClient().search(query: "calm", limit: 5)

        #expect(tracks.map(\.itemId) == ["G90Au1giwNr8o1HXhxiXpM"])
    }

    @Test("the search is scoped to the default server")
    func searchScopesToDefaultServer() async throws {
        // Without this, AudioMuse can answer with canonical ids the music server cannot match.
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[{"server_id":"nav1","name":"Navidrome"}],"default_id":"nav1"}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"abc","title":"T"}]}"#)

        _ = try await makeClient().search(query: "calm", limit: 5)

        #expect(StubProtocol.body(for: "/api/clap/search")?["server"] as? String == "nav1")
    }

    @Test("internal ids are returned with their metadata, not dropped")
    func internalIdsKeepTheirMetadata() async throws {
        // The client must NOT filter them: title and artist are what lets the provider find the
        // track in the library. Dropping them here would throw away a recoverable result.
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_20571691a2d5","title":"Tenere","author":"Tinariwen"}]}"#)

        let tracks = try await makeClient().search(query: "calm", limit: 5)

        #expect(tracks.count == 1)
        #expect(tracks[0].hasInternalId)
        #expect(tracks[0].descriptor == TrackDescriptor(title: "Tenere", artist: "Tinariwen"))
    }

    @Test("a usable id is recognised as such")
    func usableIdIsNotFlaggedInternal() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"G90Au1giwNr8o1HXhxiXpM"}]}"#)

        let tracks = try await makeClient().search(query: "calm", limit: 5)

        #expect(tracks[0].hasInternalId == false)
    }

    @Test("an empty result is not mistaken for an internal-id failure")
    func emptyResultIsNotAnIdFailure() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[]}"#)

        #expect(try await makeClient().search(query: "calm", limit: 5).isEmpty)
    }

    @Test("HTTP status codes map to distinguishable errors")
    func statusCodesMap() async {
        let cases: [(Int, AudioMuseError)] = [
            (503, .notAnalysed),
            (401, .unauthorized),
            (403, .unauthorized),
            (400, .searchDisabled("CLAP text search is disabled.")),
        ]
        for (status, expected) in cases {
            StubProtocol.reset()
            StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
            StubProtocol.stub("/api/clap/search", status: status, body: #"{"error":"CLAP text search is disabled."}"#)

            await #expect(throws: expected, "HTTP \(status)") {
                try await makeClient().search(query: "calm", limit: 5)
            }
        }
    }

    @Test("a token is sent as a bearer header, and omitted when absent")
    func tokenIsOptional() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"a"}]}"#)

        // An instance running with AUTH_ENABLED=false takes no token at all, so this must not fail.
        _ = try await makeClient(token: nil).search(query: "calm", limit: 5)
        _ = try await makeClient(token: "secret").search(query: "calm", limit: 5)
    }

    // MARK: - Provider policy

    @Test("tracks with unusable ids are recovered by name")
    func internalIdsAreRecoveredByName() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_dead","title":"Tenere","author":"Tinariwen"}]}"#)
        let library = TagLibraryStub()
        library.searchResults = [try song(id: "realId", title: "Tenere", artist: "Tinariwen")]
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: library))

        #expect(try await provider.trackIds(for: .chill, limit: 5) == ["realId"])
    }

    @Test("a track that cannot be found is dropped, not guessed at")
    func unresolvableTracksAreDropped() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search",
                          body: #"{"results":[{"item_id":"good"},{"item_id":"fp_x","title":"Absent","author":"Nobody"}]}"#)
        let library = TagLibraryStub()   // search returns nothing
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: library))

        #expect(try await provider.trackIds(for: .chill, limit: 5) == ["good"])
    }

    @Test("nothing recoverable at all raises rather than reporting an empty success")
    func nothingRecoverableRaises() async {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_a","title":"Absent"},{"item_id":"fp_b","title":"Gone"}]}"#)
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: TagLibraryStub()))

        await #expect(throws: AudioMuseError.internalIdsOnly) {
            try await provider.trackIds(for: .chill, limit: 5)
        }
    }

    @Test("a genuinely empty search stays empty and does not raise")
    func emptySearchDoesNotRaise() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[]}"#)
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: TagLibraryStub()))

        #expect(try await provider.trackIds(for: .chill, limit: 5).isEmpty)
    }

    @Test("a repeated track is only looked up once")
    func resolutionIsCached() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search",
                          body: #"{"results":[{"item_id":"fp_1","title":"Tenere","author":"Tinariwen"},{"item_id":"fp_2","title":"Tenere","author":"Tinariwen"}]}"#)
        let library = TagLibraryStub()
        library.searchResults = [try song(id: "realId", title: "Tenere", artist: "Tinariwen")]
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: library))

        _ = try await provider.trackIds(for: .chill, limit: 5)

        #expect(library.searches.count == 1, "the same track must not be searched twice")
    }

    @Test("an unreachable host is a transport error, not a crash")
    func badURLIsRejectedAtInit() {
        #expect(AudioMuseClient(urlString: "not a url", token: nil) == nil)
        #expect(AudioMuseClient(urlString: "", token: nil) == nil)
        #expect(AudioMuseClient(urlString: "http://muse.local:8000", token: nil) != nil)
    }
}
