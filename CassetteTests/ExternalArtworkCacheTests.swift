// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Testing
import Foundation
@testable import Cassette

// MARK: - Fixtures

// Minimal valid 1×1 PNG — parseable by both UIImage and NSImage.
private let validImageData: Data = {
    let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="
    return Data(base64Encoded: b64)!
}()

private let invalidImageData = Data("not_an_image".utf8)
private let testURL = URL(string: "https://coverartarchive.org/release/test/cover.jpg")!

// MARK: - Mock fetchers

@MainActor
private final class CountingFetcher: ExternalArtworkFetcher {
    private(set) var callCount = 0
    let result: Result<Data, Error>

    init(data: Data) { result = .success(data) }
    init(throwing error: Error) { result = .failure(error) }

    nonisolated func fetchData(from url: URL) async throws -> Data {
        await increment()
        switch result {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }

    private func increment() { callCount += 1 }
}

// MARK: - Helpers

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeCache(
    dir: URL,
    fetcher: (any ExternalArtworkFetcher)? = nil,
    ttl: TimeInterval = 90 * 24 * 3600,
    maxSizeBytes: Int64 = 100 * 1024 * 1024
) -> ExternalArtworkCache {
    ExternalArtworkCache(cacheDirectory: dir, fetcher: fetcher, ttl: ttl, maxSizeBytes: maxSizeBytes)
}

// MARK: - Tests

@Suite("ExternalArtworkCache")
struct ExternalArtworkCacheTests {

    // MARK: Memory cache

    @Test("memory cache hit prevents second network call")
    func memoryCacheHitSkipsNetwork() async throws {
        let dir = try makeTempDir()
        let fetcher = CountingFetcher(data: validImageData)
        let cache = makeCache(dir: dir, fetcher: fetcher)

        _ = await cache.image(for: testURL)   // network fetch + memory store
        _ = await cache.image(for: testURL)   // memory hit

        #expect(fetcher.callCount == 1)
    }

    // MARK: Disk cache

    @Test("disk hit within TTL skips network fetch and populates memory")
    func diskHitSkipsNetwork() async throws {
        let dir = try makeTempDir()

        // Warm disk via first cache instance
        let fetcher1 = CountingFetcher(data: validImageData)
        let cache1 = makeCache(dir: dir, fetcher: fetcher1)
        _ = await cache1.image(for: testURL)
        #expect(fetcher1.callCount == 1)

        // New instance = fresh memory cache, same dir, failing fetcher
        let fetcher2 = CountingFetcher(throwing: URLError(.timedOut))
        let cache2 = makeCache(dir: dir, fetcher: fetcher2)
        let result = await cache2.image(for: testURL)

        #expect(result != nil)
        #expect(fetcher2.callCount == 0)
    }

    @Test("expired disk entry triggers re-fetch and re-writes disk")
    func expiredDiskEntryRefetches() async throws {
        let dir = try makeTempDir()

        // Warm disk
        let fetcher1 = CountingFetcher(data: validImageData)
        let cache1 = makeCache(dir: dir, fetcher: fetcher1)
        _ = await cache1.image(for: testURL)

        // New instance with TTL=0 (all disk entries immediately expired)
        let fetcher2 = CountingFetcher(data: validImageData)
        let cache2 = makeCache(dir: dir, fetcher: fetcher2, ttl: 0)
        _ = await cache2.image(for: testURL)

        #expect(fetcher2.callCount == 1)
    }

    // MARK: Fetch failure

    @Test("fetch failure returns nil and writes nothing to disk")
    func fetchFailureReturnsNilWritesNothing() async throws {
        let dir = try makeTempDir()
        let fetcher = CountingFetcher(throwing: URLError(.badServerResponse))
        let cache = makeCache(dir: dir, fetcher: fetcher)

        let result = await cache.image(for: testURL)

        #expect(result == nil)

        // No file written in cache dir
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(contents.isEmpty)
    }

    // MARK: Garbage collection — TTL

    @Test("GC removes expired files and keeps files within TTL")
    func gcRemovesExpiredKeepsValid() async throws {
        let dir = try makeTempDir()
        let fm = FileManager.default

        let valid1 = dir.appendingPathComponent("valid1.jpg")
        let valid2 = dir.appendingPathComponent("valid2.jpg")
        let expired = dir.appendingPathComponent("expired.jpg")

        try Data("img".utf8).write(to: valid1)
        try Data("img".utf8).write(to: valid2)
        try Data("img".utf8).write(to: expired)

        // Backdate the expired file to 100 days ago
        let oldDate = Date(timeIntervalSinceNow: -100 * 24 * 3600)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: expired.path)

        let cache = makeCache(dir: dir, ttl: 90 * 24 * 3600)
        await cache.runGarbageCollection()

        #expect(fm.fileExists(atPath: valid1.path))
        #expect(fm.fileExists(atPath: valid2.path))
        #expect(!fm.fileExists(atPath: expired.path))
    }

    // MARK: Garbage collection — size cap

    @Test("GC size cap removes oldest files until total is under limit")
    func gcSizeCapRemovesOldest() async throws {
        let dir = try makeTempDir()
        let fm = FileManager.default

        // 5 files × 30 bytes = 150 bytes total; size cap = 100 bytes
        // After TTL phase (no files are expired), size cap must remove oldest 2:
        //   150 → remove file1 (30B) → 120 → remove file2 (30B) → 90 ≤ 100 → stop
        for i in 1...5 {
            let fileURL = dir.appendingPathComponent("file\(i).jpg")
            try Data(repeating: UInt8(i), count: 30).write(to: fileURL)
            // Space files 1 hour apart; file1 is oldest, file5 is newest
            let date = Date(timeIntervalSinceNow: TimeInterval(i - 6) * 3600)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
        }

        let cache = makeCache(dir: dir, ttl: 90 * 24 * 3600, maxSizeBytes: 100)
        await cache.runGarbageCollection()

        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("file1.jpg").path))
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("file2.jpg").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("file3.jpg").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("file4.jpg").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("file5.jpg").path))
    }
}
