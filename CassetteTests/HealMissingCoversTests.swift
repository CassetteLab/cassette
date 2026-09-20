// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
import SwiftSonic
@testable import Cassette

// MARK: - Stubs

/// Counts how many times a cover fetch was started — `_downloadCoverArt` asks for credentials
/// first, so one call here is one attempt.
@MainActor
private final class HealServerStub: ServerServiceProtocol {
    let state = ServerState()
    var baseURL: String?
    private(set) var credentialRequests = 0

    init(baseURL: String? = nil) { self.baseURL = baseURL }

    func makeSwiftSonicClient() async throws -> SwiftSonicClient {
        guard let baseURL, let url = URL(string: baseURL) else { throw CassetteError.serverNotConfigured }
        return SwiftSonicClient(configuration: ServerConfiguration(serverURL: url, username: "u", password: "p"))
    }

    func activeCredentials() async throws -> ServerCredentials {
        credentialRequests += 1
        guard baseURL != nil else { throw CassetteError.serverNotConfigured }
        return ServerCredentials(password: "p", customHeaders: [:])
    }

    func testConnection() async throws {}
    func testConnection(url: String, username: String, password: String, customHeaders: [String: String]) async throws {}
    func addServer(displayName: String, baseURL: String, username: String, password: String, customHeaders: [String: String]) async throws {}
    func setAudioMuseConfig(serverId: UUID, urlString: String?, token: String?) async throws {}
    func loadPersistedState() async {}
    func removeServer(id: UUID) async throws {}
    func setActiveServer(id: UUID) async throws {}
    func updateCustomHeaders(_ headers: [String: String], forServer id: UUID) async throws {}
    func updateServer(id: UUID, displayName: String, baseURL: String, username: String, password: String, customHeaders: [String: String]) async throws {}
    func setMusicFolderScope(serverId: UUID, folderId: String?) async throws {}
    func setHiddenPlaylistKinds(serverId: UUID, kinds: Set<PlaylistKind>) async throws {}
    func setPlaylistKindHidden(serverId: UUID, kind: PlaylistKind, isHidden: Bool) async throws {}
}

// MARK: - Tests

/// The offline covers saved beside a download are bare `{id}` files that only a download
/// writes, so once one is gone nothing restores it. `healMissingCovers` is that repair, and it
/// has to fetch exactly the missing ones and leave everything else alone.
///
/// Everything runs against a temporary directory and an in-process listener; nothing touches
/// the app's real cover directory or the network.
@Suite("Cover heal — repairs only what is missing")
@MainActor
struct HealMissingCoversTests {

    private struct Fixture {
        let base: URL
        let coverArts: URL
        let service: DownloadService
        let server: HealServerStub
    }

    /// `baseURL` non-nil means "a server is configured": credentials resolve and a fetch is
    /// really attempted (it then fails, since nothing is listening). Nil means unconfigured or
    /// offline — `activeCredentials` throws before any request is built.
    private func makeFixture(serverConfigured: Bool) throws -> Fixture {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cassette-heal-\(UUID().uuidString)", isDirectory: true)
        let server = HealServerStub(baseURL: serverConfigured ? "http://127.0.0.1:9" : nil)
        let service = DownloadService(
            serverService: server,
            modelContainer: try ModelContainer.cassette(inMemory: true),
            toastService: ToastService(),
            cacheSettings: CacheSettings(),
            baseDirectory: base
        )
        return Fixture(
            base: base,
            coverArts: base.appendingPathComponent("coverarts", isDirectory: true),
            service: service,
            server: server
        )
    }

    // The FileManager work below is `nonisolated` on purpose. This suite is @MainActor for the
    // stubs that need it, and holding that actor across synchronous file I/O is contention every
    // other suite pays for: their continuations queue behind it.
    private nonisolated func exists(_ f: Fixture, _ id: String) -> Bool {
        FileManager.default.fileExists(atPath: f.coverArts.appendingPathComponent(id).path)
    }

    private nonisolated func contents(_ f: Fixture, _ id: String) -> Data? {
        try? Data(contentsOf: f.coverArts.appendingPathComponent(id))
    }

    private nonisolated func tearDown(_ f: Fixture) {
        try? FileManager.default.removeItem(at: f.base)
    }

    @Test("a missing cover is fetched")
    func missingCoverIsFetched() async throws {
        let f = try makeFixture(serverConfigured: true)
        defer { tearDown(f) }

        #expect(!exists(f, "al-1"), "precondition: the cover really is missing")

        _ = await f.service.healMissingCovers(referencedIds: ["al-1"])

        #expect(f.server.credentialRequests == 1, "the missing cover was fetched")
    }

    @Test("a cover already on disk is never fetched again")
    func presentCoverIsNotRefetched() async throws {
        let f = try makeFixture(serverConfigured: true)
        defer { tearDown(f) }

        let original = Data("already here".utf8)
        await f.service.persistCover(original, forId: "al-1")

        let repaired = await f.service.healMissingCovers(referencedIds: ["al-1"])

        #expect(repaired == 0)
        #expect(f.server.credentialRequests == 0, "no fetch was even started")
        #expect(contents(f, "al-1") == original, "the existing file is untouched")
    }

    @Test("only the missing ids are fetched when the set is mixed")
    func onlyMissingAreFetched() async throws {
        let f = try makeFixture(serverConfigured: true)
        defer { tearDown(f) }

        await f.service.persistCover(Data("kept".utf8), forId: "present-1")
        await f.service.persistCover(Data("kept".utf8), forId: "present-2")

        let repaired = await f.service.healMissingCovers(
            referencedIds: ["present-1", "present-2", "missing-1", "missing-2"]
        )

        // The count is what the filter actually guarantees. `_downloadCoverArt` has its own
        // `!fileExists` guard, so a present cover costs no credential request either way —
        // but without the filter it still counts as "repaired", and the log lies.
        #expect(repaired == 0, "nothing was reachable, so nothing was repaired")
        #expect(f.server.credentialRequests == 2, "exactly one attempt per missing cover, none for the present ones")
        #expect(contents(f, "present-1") == Data("kept".utf8))
        #expect(contents(f, "present-2") == Data("kept".utf8))
    }

    @Test("offline writes nothing and swallows every failure")
    func offlineHealsNothing() async throws {
        // No server configured: `activeCredentials` throws, which is what offline looks like
        // from here. The pass must return quietly rather than propagate or leave partial files.
        let f = try makeFixture(serverConfigured: false)
        defer { tearDown(f) }

        let repaired = await f.service.healMissingCovers(referencedIds: ["al-1", "al-2"])

        #expect(repaired == 0)
        #expect(!exists(f, "al-1"))
        #expect(!exists(f, "al-2"))
    }

    @Test("an empty set asks for nothing at all")
    func emptySetIsANoOp() async throws {
        let f = try makeFixture(serverConfigured: false)
        defer { tearDown(f) }

        let repaired = await f.service.healMissingCovers(referencedIds: [])

        #expect(repaired == 0)
        #expect(f.server.credentialRequests == 0)
    }
}
