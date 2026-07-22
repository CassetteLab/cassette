// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftMuse
@testable import Cassette

// The SwiftMuseClient itself — search, scoping, status mapping, auth, decoding — is covered by the
// SwiftMuse package's own test suite. These tests cover only what stays in the app: the provider
// policy that turns AudioMuse results into playable ids, recovering unusable `fp_` ids by name.

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

/// A SwiftMuseClient wired to the stub above. Scoping is left at `.none`, so search makes a single
/// `/api/clap/search` call — the provider policy under test never depends on server scoping.
private func makeClient(token: String? = nil) -> SwiftMuseClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    let transport = URLSessionTransport(session: URLSession(configuration: config))
    let museConfig = SwiftMuseConfiguration(urlString: "http://muse.local:8000", token: token)!
    return SwiftMuseClient(configuration: museConfig, transport: transport)
}

@Suite("AudioMuse provider policy", .serialized)
struct AudioMuseProviderTests {

    @Test("tracks with unusable ids are recovered by name")
    func internalIdsAreRecoveredByName() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_dead","title":"Tenere","author":"Tinariwen"}]}"#)
        let library = TagLibraryStub()
        library.searchResults = [try song(id: "realId", title: "Tenere", artist: "Tinariwen")]
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: library))

        #expect(try await provider.trackIds(for: .chill, limit: 5) == ["realId"])
    }

    @Test("a track that cannot be found is dropped, not guessed at")
    func unresolvableTracksAreDropped() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/clap/search",
                          body: #"{"results":[{"item_id":"good"},{"item_id":"fp_x","title":"Absent","author":"Nobody"}]}"#)
        let library = TagLibraryStub()   // search returns nothing
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: library))

        #expect(try await provider.trackIds(for: .chill, limit: 5) == ["good"])
    }

    @Test("nothing recoverable at all raises rather than reporting an empty success")
    func nothingRecoverableRaises() async {
        StubProtocol.reset()
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_a","title":"Absent"},{"item_id":"fp_b","title":"Gone"}]}"#)
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: TagLibraryStub()))

        await #expect(throws: MoodProviderError.internalIdsOnly) {
            try await provider.trackIds(for: .chill, limit: 5)
        }
    }

    @Test("a genuinely empty search stays empty and does not raise")
    func emptySearchDoesNotRaise() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/clap/search", body: #"{"results":[]}"#)
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: TagLibraryStub()))

        #expect(try await provider.trackIds(for: .chill, limit: 5).isEmpty)
    }

    @Test("a repeated track is only looked up once")
    func resolutionIsCached() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/clap/search",
                          body: #"{"results":[{"item_id":"fp_1","title":"Tenere","author":"Tinariwen"},{"item_id":"fp_2","title":"Tenere","author":"Tinariwen"}]}"#)
        let library = TagLibraryStub()
        library.searchResults = [try song(id: "realId", title: "Tenere", artist: "Tinariwen")]
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: library))

        _ = try await provider.trackIds(for: .chill, limit: 5)

        #expect(library.searches.count == 1, "the same track must not be searched twice")
    }

    @Test("the descriptor maps title and artist for by-name lookup")
    func descriptorMapsMetadata() {
        let track = SonicTrack(itemID: "fp_x", title: "Tenere", author: "Tinariwen")
        #expect(track.descriptor == TrackDescriptor(title: "Tenere", artist: "Tinariwen"))
        // A result with no title cannot be looked up — the descriptor must refuse it.
        #expect(SonicTrack(itemID: "fp_y", title: nil).descriptor == nil)
    }
}
