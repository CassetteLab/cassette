// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
@testable import Cassette

/// Both cover caches share one directory and are told apart only by the `@` in the filename.
/// These pin the split: clearing takes the re-fetchable tier files, and never the bare `{id}`
/// covers saved with offline downloads — deleting those would leave a downloaded album with no
/// artwork in airplane mode, with no way to get it back short of downloading the tracks again.
@Suite("Cover cache — clearing keeps offline artwork")
@MainActor
struct ClearStreamingCoversTests {

    private var coverArtsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.cassette", isDirectory: true)
            .appendingPathComponent("coverarts", isDirectory: true)
    }

    private func makeService() throws -> DownloadService {
        DownloadService(
            serverService: MockServerService(),
            modelContainer: try ModelContainer.cassette(inMemory: true),
            toastService: ToastService(),
            cacheSettings: CacheSettings()
        )
    }

    /// Unique per run so a failed test can't poison the next one; the suite cleans up after itself.
    private func seed(_ service: DownloadService, prefix: String) async -> (tiers: [String], bare: String) {
        let bare = "\(prefix)-offline"
        let tiers = ["\(prefix)-cached@thumb", "\(prefix)-cached@hero", "\(bare)@thumb"]
        for name in tiers + [bare] {
            await service.persistCover(Data([0x89, 0x50, 0x4E, 0x47]), forId: name)
        }
        return (tiers, bare)
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: coverArtsDirectory.appendingPathComponent(name).path)
    }

    private func cleanUp(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: coverArtsDirectory.appendingPathComponent(name))
        }
    }

    @Test("clearStreamingCovers removes tier files and keeps the bare offline cover")
    func clearsOnlyTierFiles() async throws {
        let service = try makeService()
        let (tiers, bare) = await seed(service, prefix: "clear-\(UUID().uuidString.prefix(8))")
        defer { cleanUp(tiers + [bare]) }

        for name in tiers { #expect(exists(name), "seed failed for \(name)") }
        #expect(exists(bare))

        let removed = await service.clearStreamingCovers()

        for name in tiers { #expect(!exists(name), "\(name) should have been cleared") }
        #expect(exists(bare), "the offline download's cover must survive a cache clear")
        #expect(removed >= tiers.count)
    }

    @Test("garbageCollectOrphanedCovers is the exact complement — it never takes tier files")
    func gcKeepsTierFiles() async throws {
        let service = try makeService()
        let (tiers, bare) = await seed(service, prefix: "gc-\(UUID().uuidString.prefix(8))")
        defer { cleanUp(tiers + [bare]) }

        // Nothing is referenced, so every bare file is an orphan and should go.
        _ = await service.garbageCollectOrphanedCovers(referencedIds: [])

        for name in tiers { #expect(exists(name), "\(name) is streaming cache, not GC's business") }
        #expect(!exists(bare), "an unreferenced offline cover is what GC is for")
    }

    @Test("a referenced offline cover survives garbage collection")
    func gcKeepsReferencedCover() async throws {
        let service = try makeService()
        let (tiers, bare) = await seed(service, prefix: "ref-\(UUID().uuidString.prefix(8))")
        defer { cleanUp(tiers + [bare]) }

        _ = await service.garbageCollectOrphanedCovers(referencedIds: [bare])

        #expect(exists(bare))
    }
}
