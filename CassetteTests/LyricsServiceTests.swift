// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
import SwiftSonic
@testable import Cassette

// MARK: - Minimal mock for LyricsService construction

@MainActor
final class MockLyricsServerService: ServerServiceProtocol {
    let state: ServerState = ServerState()
    func addServer(displayName: String, baseURL: String, username: String, password: String, customHeaders: [String: String]) async throws {}
    func removeServer(id: UUID) async throws {}
    func setActiveServer(id: UUID) async throws {}
    func updateCustomHeaders(_ headers: [String: String], forServer id: UUID) async throws {}
    func testConnection() async throws {}
    func testConnection(url: String, username: String, password: String, customHeaders: [String: String]) async throws {}
    func makeSwiftSonicClient() async throws -> SwiftSonicClient { throw CassetteError.notImplemented }
    func activeCredentials() async throws -> ServerCredentials { throw CassetteError.notImplemented }
    func loadPersistedState() async {}
}

// MARK: - Helpers

@MainActor
private func makeService() throws -> (LyricsService, ModelContainer) {
    let container = try ModelContainer(
        for: Schema([CachedLyrics.self]),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let mock = MockLyricsServerService()
    let service = LyricsService(serverService: mock, modelContainer: container)
    return (service, container)
}

private func sampleList() -> LyricsList {
    LyricsList(structuredLyrics: [
        StructuredLyrics(lang: "en", synced: true, line: [Line(value: "Hello", start: 0)]),
        StructuredLyrics(lang: "fr", synced: false, line: [Line(value: "Bonjour")])
    ])
}

// MARK: - selectBestLanguage

@Suite("LyricsService — selectBestLanguage")
@MainActor
struct LyricsSelectBestLanguageTests {

    @Test func emptyList_returnsNil() {
        let (service, _) = try! makeService()
        let result = service.selectBestLanguage(from: LyricsList(structuredLyrics: []))
        #expect(result == nil)
    }

    @Test func preferred_syncedVariantChosen() {
        let list = LyricsList(structuredLyrics: [
            StructuredLyrics(lang: "fr", synced: false, line: []),
            StructuredLyrics(lang: "fr", synced: true, line: [])
        ])
        let (service, _) = try! makeService()
        let result = service.selectBestLanguage(from: list, preferred: "fr")
        #expect(result?.synced == true)
    }

    @Test func preferred_unsyncedFallback_whenNoSynced() {
        let list = LyricsList(structuredLyrics: [
            StructuredLyrics(lang: "fr", synced: false, line: [])
        ])
        let (service, _) = try! makeService()
        let result = service.selectBestLanguage(from: list, preferred: "fr")
        #expect(result?.lang == "fr")
        #expect(result?.synced == false)
    }

    @Test func locale_frFR_picksFrenchUnsynced_overEnglishSynced() {
        let (service, _) = try! makeService()
        let result = service.selectBestLanguage(from: sampleList(), locale: Locale(identifier: "fr_FR"))
        #expect(result?.lang == "fr")
    }

    @Test func locale_enUS_picksSyncedEnglish() {
        let (service, _) = try! makeService()
        let result = service.selectBestLanguage(from: sampleList(), locale: Locale(identifier: "en_US"))
        #expect(result?.lang == "en")
        #expect(result?.synced == true)
    }

    @Test func noLocaleMatch_returnFirstSynced() {
        let list = LyricsList(structuredLyrics: [
            StructuredLyrics(lang: "ja", synced: false, line: []),
            StructuredLyrics(lang: "ko", synced: true, line: [])
        ])
        let (service, _) = try! makeService()
        let result = service.selectBestLanguage(from: list, locale: Locale(identifier: "fr_FR"))
        #expect(result?.lang == "ko")
        #expect(result?.synced == true)
    }

    @Test func xxx_normalizedToUnd() {
        let list = LyricsList(structuredLyrics: [
            StructuredLyrics(lang: "xxx", synced: true, line: [])
        ])
        let (service, _) = try! makeService()
        let result = service.selectBestLanguage(from: list, preferred: "und")
        #expect(result?.synced == true)
    }
}

// MARK: - Cache hit

@Suite("LyricsService — cache")
@MainActor
struct LyricsCacheTests {

    @Test func cacheHit_returnsWithoutNetwork() async throws {
        let (service, container) = try makeService()
        let serverId = UUID()
        let songId = "song-xyz"
        let list = sampleList()

        // Pre-populate cache directly via ModelContext
        let data = try JSONEncoder().encode(list)
        await MainActor.run {
            let ctx = ModelContext(container)
            ctx.insert(CachedLyrics(songId: songId, serverId: serverId, jsonPayload: data))
            try? ctx.save()
        }

        // fetchLyrics should return from cache; MockLyricsServerService throws on makeSwiftSonicClient
        let result = try await service.fetchLyrics(forSongId: songId, serverId: serverId)
        #expect(result == list)
    }
}
