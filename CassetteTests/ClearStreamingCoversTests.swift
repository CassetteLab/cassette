// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
@testable import Cassette

/// Both cover caches share one directory and are told apart only by the `@` in the filename:
/// `{id}@thumb` / `{id}@hero` are re-fetchable streaming cache, while a bare `{id}` is the cover
/// captured alongside an offline download, which nothing re-creates short of downloading the
/// tracks again. Deleting the wrong ones leaves a downloaded album with no artwork in airplane
/// mode, so both clearing paths are pinned here against real files.
///
/// Every test runs against its own temporary directory. The app's real one lives under
/// Documents, shared with every other suite and with the app host — whose launch-time legacy
/// sweep deletes bare `{id}` files from a detached task — so a test that wrote there would race
/// rather than measure.
@Suite("Cover cache — offline artwork survives clearing")
@MainActor
struct ClearStreamingCoversTests {

    private struct Fixture {
        let base: URL
        let coverArts: URL
        let service: DownloadService
        let tiers: [String]
        let bare: [String]
    }

    private func makeFixture() throws -> Fixture {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cassette-covers-\(UUID().uuidString)", isDirectory: true)
        let service = DownloadService(
            serverService: MockServerService(),
            modelContainer: try ModelContainer.cassette(inMemory: true),
            toastService: ToastService(),
            cacheSettings: CacheSettings(),
            baseDirectory: base
        )
        return Fixture(
            base: base,
            coverArts: base.appendingPathComponent("coverarts", isDirectory: true),
            service: service,
            tiers: ["al-1@thumb", "al-1@hero", "pl-7@thumb"],
            bare: ["al-1", "pl-7", "al-99"]
        )
    }

    private func seed(_ f: Fixture) async {
        for name in f.tiers + f.bare {
            await f.service.persistCover(Data([0x89, 0x50, 0x4E, 0x47]), forId: name)
        }
    }

    // The FileManager work below is `nonisolated` on purpose. This suite is @MainActor for the
    // pieces that genuinely need it — ArtworkImageCache and the launch-time wipe — and holding
    // that actor across synchronous file I/O is contention every other suite pays for: their
    // continuations queue behind it. It buys this suite nothing to hold it.
    private nonisolated func exists(_ f: Fixture, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: f.coverArts.appendingPathComponent(name).path)
    }

    private nonisolated func tearDown(_ f: Fixture) {
        try? FileManager.default.removeItem(at: f.base)
    }

    @Test("clearStreamingCovers deletes the tier files and leaves the offline covers")
    func clearKeepsOfflineCovers() async throws {
        let f = try makeFixture()
        defer { tearDown(f) }
        await seed(f)
        for name in f.tiers + f.bare { #expect(exists(f, name), "seed failed for \(name)") }

        let removed = await f.service.clearStreamingCovers()

        #expect(removed == f.tiers.count)
        for name in f.tiers { #expect(!exists(f, name), "\(name) should have been cleared") }
        for name in f.bare { #expect(exists(f, name), "offline cover \(name) must survive a cache clear") }
    }

    @Test("invalidateCoverArtCacheIfNeeded leaves the offline covers too")
    func launchWipeKeepsOfflineCovers() async throws {
        let f = try makeFixture()
        defer { tearDown(f) }
        await seed(f)

        // The version gate is what decides whether the wipe runs at all; force it to.
        let versionKey = "cassette.coverArtCacheVersion"
        let previous = UserDefaults.standard.integer(forKey: versionKey)
        UserDefaults.standard.set(0, forKey: versionKey)
        defer { UserDefaults.standard.set(previous, forKey: versionKey) }

        let cache = ArtworkImageCache(
            downloadService: f.service,
            libraryService: CoverTestLibraryService()
        )
        await AppContainer.invalidateCoverArtCacheIfNeeded(artworkCache: cache)

        for name in f.tiers { #expect(!exists(f, name), "\(name) is re-fetchable and should go") }
        for name in f.bare {
            #expect(exists(f, name), "offline cover \(name) must survive the launch-time wipe")
        }
    }

    @Test("clearing an already-clean directory is a no-op, not a failure")
    func clearIsIdempotent() async throws {
        let f = try makeFixture()
        defer { tearDown(f) }
        await seed(f)

        _ = await f.service.clearStreamingCovers()
        let second = await f.service.clearStreamingCovers()

        #expect(second == 0)
        for name in f.bare { #expect(exists(f, name)) }
    }

    /// The launch sequence used to hold a second deleter: a one-shot sweep that removed every
    /// file without a tier suffix, which is precisely the naming offline downloads use. This
    /// walks the whole of what launch does to the cover directory and asserts the bare files
    /// are still there afterwards.
    @Test("no launch-time path deletes an offline cover")
    func launchLeavesOfflineCoversAlone() async throws {
        let f = try makeFixture()
        defer { tearDown(f) }
        await seed(f)

        let versionKey = "cassette.coverArtCacheVersion"
        let previous = UserDefaults.standard.integer(forKey: versionKey)
        UserDefaults.standard.set(0, forKey: versionKey)
        defer { UserDefaults.standard.set(previous, forKey: versionKey) }

        let cache = ArtworkImageCache(
            downloadService: f.service,
            libraryService: CoverTestLibraryService()
        )
        // Everything launch does that touches this directory, in order.
        await AppContainer.invalidateCoverArtCacheIfNeeded(artworkCache: cache)
        _ = await f.service.garbageCollectOrphanedCovers(referencedIds: Set(f.bare))

        for name in f.bare {
            #expect(exists(f, name), "launch must not remove offline cover \(name)")
        }
    }

    @Test("garbage collection is the exact complement: bare ids only, tier files untouched")
    func gcIsTheComplement() async throws {
        let f = try makeFixture()
        defer { tearDown(f) }
        await seed(f)

        // "al-1" is still referenced by a download; the other bare covers are orphans.
        _ = await f.service.garbageCollectOrphanedCovers(referencedIds: ["al-1"])

        for name in f.tiers { #expect(exists(f, name), "\(name) is streaming cache, not GC's business") }
        #expect(exists(f, "al-1"), "a referenced offline cover must survive collection")
        #expect(!exists(f, "pl-7"), "an unreferenced offline cover is what GC is for")
        #expect(!exists(f, "al-99"))
    }
}
