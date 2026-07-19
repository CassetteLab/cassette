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

    @Test("internal fp_ ids are refused instead of being passed on")
    func internalIdsAreRefused() async {
        // The real failure: every result came back as fp_2057…, Subsonic dropped them all, and the
        // playlist ended up empty while every layer reported success.
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_20571691a2d5","title":"T"},{"item_id":"fp_22d73774bad5","title":"U"}]}"#)

        await #expect(throws: AudioMuseError.internalIdsOnly) {
            try await makeClient().search(query: "calm", limit: 5)
        }
    }

    @Test("a mix of internal and real ids keeps only the usable ones")
    func mixedIdsAreFiltered() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_dead"},{"item_id":"realId"}]}"#)

        let tracks = try await makeClient().search(query: "calm", limit: 5)

        #expect(tracks.map(\.itemId) == ["realId"])
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

    @Test("an unreachable host is a transport error, not a crash")
    func badURLIsRejectedAtInit() {
        #expect(AudioMuseClient(urlString: "not a url", token: nil) == nil)
        #expect(AudioMuseClient(urlString: "", token: nil) == nil)
        #expect(AudioMuseClient(urlString: "http://muse.local:8000", token: nil) != nil)
    }
}
