// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftSonic
@testable import Cassette

// MARK: - Stubs

private struct ShareStubFailure: Error {}

/// Hands ShareService a real `SwiftSonicClient` wired to a stub transport, so the tests drive the
/// actual decoding and error paths rather than a hand-made fake of them.
/// `StubHTTPTransport` comes from ConnectionTestErrorMappingTests.
@MainActor
private final class ShareStubServerService: ServerServiceProtocol {
    let state = ServerState()
    private let transport: StubHTTPTransport
    private(set) var clientBuilds = 0

    init(transport: StubHTTPTransport) {
        self.transport = transport
    }

    func makeSwiftSonicClient() async throws -> SwiftSonicClient {
        clientBuilds += 1
        guard let url = URL(string: "https://stub.example.com") else { throw ShareStubFailure() }
        return SwiftSonicClient(
            configuration: ServerConfiguration(serverURL: url, username: "u", password: "p"),
            transport: transport,
            retryPolicy: .none
        )
    }

    func addServer(displayName: String, baseURL: String, username: String, password: String, customHeaders: [String: String]) async throws {}
    func removeServer(id: UUID) async throws {}
    func setActiveServer(id: UUID) async throws {}
    func updateCustomHeaders(_ headers: [String: String], forServer id: UUID) async throws {}
    func updateServer(id: UUID, displayName: String, baseURL: String, username: String, password: String, customHeaders: [String: String]) async throws {}
    func setMusicFolderScope(serverId: UUID, folderId: String?) async throws {}
    func setHiddenPlaylistKinds(serverId: UUID, kinds: Set<PlaylistKind>) async throws {}
    func setPlaylistKindHidden(serverId: UUID, kind: PlaylistKind, isHidden: Bool) async throws {}
    func setAudioMuseConfig(serverId: UUID, urlString: String?, token: String?) async throws {}
    func testConnection() async throws {}
    func testConnection(url: String, username: String, password: String, customHeaders: [String: String]) async throws {}
    func activeCredentials() async throws -> ServerCredentials { throw ShareStubFailure() }
    func loadPersistedState() async {}
}

// MARK: - JSON

private func createShareOKJSON(url: String) -> Data {
    Data("""
    {"subsonic-response":{"status":"ok","version":"1.16.1","shares":{"share":[
    {"id":"sh-1","url":"\(url)","username":"alice","created":"2026-10-16T10:00:00.000Z","visitCount":0}]}}}
    """.utf8)
}

private func emptySharesJSON() -> Data {
    Data(#"{"subsonic-response":{"status":"ok","version":"1.16.1","shares":{}}}"#.utf8)
}

private func apiErrorJSON(code: Int) -> Data {
    Data("""
    {"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":\(code),"message":"nope"}}}
    """.utf8)
}

// MARK: - Mapping

@Suite("ShareLinkError")
struct ShareLinkErrorTests {

    @Test("a network error is reported as an unreachable server")
    func urlErrorIsUnreachable() {
        #expect(ShareLinkError(URLError(.timedOut)) == .unreachable)
    }

    @Test("an already-mapped error passes through unchanged")
    func passesThroughItself() {
        #expect(ShareLinkError(ShareLinkError.notPermitted) == .notPermitted)
    }

    @Test("anything unrecognised stays vague on purpose")
    func unknownErrorIsOther() {
        struct Nonsense: Error {}
        #expect(ShareLinkError(Nonsense()) == .other)
    }

    @Test("every case says something, and the two actionable ones do not say the same thing")
    func messages() {
        let cases: [ShareLinkError] = [.sharingUnavailable, .notPermitted, .unreachable, .other]
        for error in cases {
            #expect(!error.userMessage.isEmpty)
        }
        // One sends you to the server's config, the other to its admin: they must not collapse.
        #expect(ShareLinkError.sharingUnavailable.userMessage != ShareLinkError.notPermitted.userMessage)
    }
}

// MARK: - Service

@Suite("ShareService")
@MainActor
struct ShareServiceTests {

    private func makeService(_ outcome: StubHTTPTransport.Outcome) -> (ShareService, ShareStubServerService) {
        let server = ShareStubServerService(transport: StubHTTPTransport(outcome: outcome))
        return (ShareService(serverService: server), server)
    }

    @Test("a created share comes back as the URL the server returned")
    func returnsServerURL() async throws {
        let (service, _) = makeService(.response(
            data: createShareOKJSON(url: "https://music.example.com/share/sh-1"),
            statusCode: 200
        ))
        let url = try await service.createPublicLink(songIds: ["song-1"], description: "A song")
        #expect(url.absoluteString == "https://music.example.com/share/sh-1")
    }

    @Test("a server without the endpoint reads as sharing being unavailable")
    func notFoundIsUnavailable() async throws {
        let (service, _) = makeService(.response(data: apiErrorJSON(code: 70), statusCode: 200))
        await #expect(throws: ShareLinkError.sharingUnavailable) {
            try await service.createPublicLink(songIds: ["song-1"], description: nil)
        }
    }

    @Test("a generic failure also reads as sharing being unavailable — it is how a disabled feature answers")
    func genericIsUnavailable() async throws {
        let (service, _) = makeService(.response(data: apiErrorJSON(code: 0), statusCode: 200))
        await #expect(throws: ShareLinkError.sharingUnavailable) {
            try await service.createPublicLink(songIds: ["song-1"], description: nil)
        }
    }

    @Test("a refused account is reported as a permission problem, not a missing feature")
    func unauthorizedIsNotPermitted() async throws {
        let (service, _) = makeService(.response(data: apiErrorJSON(code: 50), statusCode: 200))
        await #expect(throws: ShareLinkError.notPermitted) {
            try await service.createPublicLink(songIds: ["song-1"], description: nil)
        }
    }

    @Test("a server that cannot be reached is reported as such")
    func transportFailureIsUnreachable() async throws {
        let (service, _) = makeService(.urlError(.cannotFindHost))
        await #expect(throws: ShareLinkError.unreachable) {
            try await service.createPublicLink(songIds: ["song-1"], description: nil)
        }
    }

    @Test("an accepted request that returns no share is still a failure")
    func emptyResponseFails() async throws {
        let (service, _) = makeService(.response(data: emptySharesJSON(), statusCode: 200))
        await #expect(throws: ShareLinkError.other) {
            try await service.createPublicLink(songIds: ["song-1"], description: nil)
        }
    }

    @Test("no songs means no request at all")
    func emptySelectionNeverHitsTheServer() async throws {
        let (service, server) = makeService(.response(
            data: createShareOKJSON(url: "https://music.example.com/share/sh-1"),
            statusCode: 200
        ))
        await #expect(throws: ShareLinkError.other) {
            try await service.createPublicLink(songIds: [], description: nil)
        }
        #expect(server.clientBuilds == 0)
    }
}
