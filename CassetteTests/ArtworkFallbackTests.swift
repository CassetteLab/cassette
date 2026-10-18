// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
import SwiftData
@testable import Cassette

@Suite("Artwork fallback across sizes")
@MainActor
struct ArtworkFallbackTests {
    private let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg==")!

    private struct Fixture {
        let directory: URL
        let server: MockServerService
        let downloads: DownloadService
        let cache: ArtworkImageCache
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("artwork-fallback-\(UUID().uuidString)", isDirectory: true)
        let server = MockServerService()
        let downloads = DownloadService(
            serverService: server,
            modelContainer: try ModelContainer.cassette(inMemory: true),
            toastService: ToastService(),
            cacheSettings: CacheSettings(),
            baseDirectory: directory
        )
        let cache = ArtworkImageCache(
            downloadService: downloads,
            libraryService: CoverTestLibraryService(),
            revalidationStore: CoverRevalidationStore(fileURL: directory.appendingPathComponent("revalidation.json"))
        )
        return Fixture(directory: directory, server: server, downloads: downloads, cache: cache)
    }

    private nonisolated func removeFixture(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.directory)
    }

    @Test("a custom photo is available to grids even without a server upload")
    func customPhotoIsAvailableAtEverySize() async throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let versionKey = "coverArtUploadVersion"
        let previousVersion = UserDefaults.standard.object(forKey: versionKey)
        defer { UserDefaults.standard.set(previousVersion, forKey: versionKey) }
        let manager = PlaylistCoverManager(
            serverState: fixture.server.state,
            serverService: fixture.server,
            downloadService: fixture.downloads,
            artworkImageCache: fixture.cache
        )
        await fixture.downloads.persistCover(Data("old cover".utf8), forId: "playlist@grid")

        await manager.applyImageCover(imageData, playlistId: "playlist")

        for tier in ArtworkTier.allCases {
            let url = try #require(await fixture.downloads.localCoverArtURL(forId: "playlist@\(tier.rawValue)"))
            #expect(try Data(contentsOf: url) == imageData)
        }
        #expect(await fixture.cache.load(coverArtId: "playlist", tier: .grid) != nil)
    }

    @Test("a detail transition reuses the grid image without a thumbnail")
    func initialImageUsesCachedGrid() async throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        await fixture.downloads.persistCover(imageData, forId: "album@grid")
        let grid = try #require(await fixture.cache.load(coverArtId: "album", tier: .grid))

        #expect(fixture.cache.cachedImage(for: "album", tier: .thumb) == nil)
        #expect(fixture.cache.cachedImage(for: "album", tier: .hero) == nil)
        #expect(fixture.cache.cachedImage(for: "album") === grid)
        #expect(fixture.cache.cachedImage(for: "another-album") == nil)
    }

    @Test("the initial image uses the highest cached resolution")
    func initialImagePrefersHigherResolution() async throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        for tier in [ArtworkTier.hero, .grid, .thumb] {
            await fixture.downloads.persistCover(imageData, forId: "album@\(tier.rawValue)")
            _ = await fixture.cache.load(coverArtId: "album", tier: tier)
        }
        let hero = try #require(fixture.cache.cachedImage(for: "album", tier: .hero))
        #expect(fixture.cache.cachedImage(for: "album") === hero)
    }

    @Test("a hero can use the grid file offline with an empty memory cache")
    func offlineHeroUsesGridFile() async throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        await fixture.downloads.persistCover(imageData, forId: "album@grid")

        #expect(fixture.cache.cachedImage(for: "album") == nil)
        #expect(await fixture.cache.localImage(for: "album", tier: .hero) != nil)
        #expect(await fixture.cache.localImage(for: "another-album", tier: .hero) == nil)
        #expect(fixture.cache.cachedImage(for: "album", tier: .hero) == nil)
    }
}
