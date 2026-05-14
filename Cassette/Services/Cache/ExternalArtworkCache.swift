// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import CryptoKit
import OSLog
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Fetcher protocol (testability seam)

protocol ExternalArtworkFetcher: Sendable {
    func fetchData(from url: URL) async throws -> Data
}

struct URLSessionExternalFetcher: ExternalArtworkFetcher {
    private let session: URLSession

    nonisolated init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Cache actor

/// Disk + memory cache for external cover art (e.g. Cover Art Archive).
/// Resolution order: memory LRU → disk (Caches/app.cassette/external-covers/) → network.
/// Disk entries expire after 90 days; GC enforces a 100 MB size cap on top of TTL.
actor ExternalArtworkCache {

    // MARK: - Configuration

    private let ttl: TimeInterval
    private let maxSizeBytes: Int64
    private let maxMemoryEntries: Int

    // MARK: - Storage

    private let cacheDirectory: URL
    private let fetcher: any ExternalArtworkFetcher

    // MARK: - Memory cache (LRU, keyed by URL)

    private var memoryCache: [URL: PlatformImage] = [:]
    private var accessOrder: [URL] = []

    // MARK: - Init

    init(
        cacheDirectory: URL? = nil,
        fetcher: (any ExternalArtworkFetcher)? = nil,
        ttl: TimeInterval = 90 * 24 * 3600,
        maxSizeBytes: Int64 = 100 * 1024 * 1024,
        maxMemoryEntries: Int = 30
    ) {
        let dir: URL
        if let cacheDirectory {
            dir = cacheDirectory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            dir = caches.appendingPathComponent("app.cassette/external-covers", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDirectory = dir
        self.fetcher = fetcher ?? URLSessionExternalFetcher()
        self.ttl = ttl
        self.maxSizeBytes = maxSizeBytes
        self.maxMemoryEntries = maxMemoryEntries
    }

    // MARK: - Public API

    func image(for url: URL) async -> PlatformImage? {
        // 1. Memory hit
        if let hit = memoryCache[url] {
            touchMemory(url)
            Logger.externalArtwork.debug("ExternalArtworkCache: memory hit \(url.lastPathComponent, privacy: .public)")
            return hit
        }

        // 2. Disk hit (within TTL)
        let fileURL = diskURL(for: url)
        if let image = diskImage(at: fileURL) {
            storeMemory(image, for: url)
            Logger.externalArtwork.debug("ExternalArtworkCache: disk hit \(url.lastPathComponent, privacy: .public)")
            return image
        }

        // 3. Network fetch — never write on failure
        do {
            let data = try await fetcher.fetchData(from: url)
            guard let image = PlatformImage(data: data) else {
                Logger.externalArtwork.warning("ExternalArtworkCache: corrupt data from \(url, privacy: .public)")
                return nil
            }
            try? data.write(to: fileURL, options: .atomic)
            storeMemory(image, for: url)
            Logger.externalArtwork.debug("ExternalArtworkCache: fetched + cached \(url.lastPathComponent, privacy: .public)")
            return image
        } catch {
            Logger.externalArtwork.warning("ExternalArtworkCache: fetch failed for \(url, privacy: .public) — \(error, privacy: .public)")
            return nil
        }
    }

    func clearMemoryCache() {
        memoryCache.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Garbage collection

    /// Purges expired files (modification date > TTL), then enforces the size cap
    /// by deleting the oldest surviving files until total is under maxSizeBytes.
    func runGarbageCollection() {
        let fm = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let contents = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: .skipsHiddenFiles
        ) else { return }

        let expiryDate = Date(timeIntervalSinceNow: -ttl)
        var survivors: [(url: URL, modDate: Date, size: Int64)] = []
        var expiredCount = 0

        // Phase 1: TTL purge
        for fileURL in contents {
            let values = try? fileURL.resourceValues(forKeys: resourceKeys)
            let modDate = values?.contentModificationDate ?? .distantPast
            let size = Int64(values?.fileSize ?? 0)

            if modDate < expiryDate {
                try? fm.removeItem(at: fileURL)
                expiredCount += 1
            } else {
                survivors.append((fileURL, modDate, size))
            }
        }

        // Phase 2: size cap — delete oldest first until total <= maxSizeBytes
        let totalSize = survivors.reduce(0) { $0 + $1.size }
        var capRemovedCount = 0
        if totalSize > maxSizeBytes {
            let sorted = survivors.sorted { $0.modDate < $1.modDate }
            var runningSize = totalSize
            for entry in sorted {
                guard runningSize > maxSizeBytes else { break }
                try? fm.removeItem(at: entry.url)
                runningSize -= entry.size
                capRemovedCount += 1
            }
        }

        Logger.externalArtwork.info("ExternalArtworkCache: GC done — \(expiredCount) expired, \(capRemovedCount) over cap")
    }

    // MARK: - Private helpers

    private func diskURL(for url: URL) -> URL {
        cacheDirectory.appendingPathComponent(sha256(url.absoluteString) + ".jpg")
    }

    private func diskImage(at fileURL: URL) -> PlatformImage? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let modDate = attrs?[.modificationDate] as? Date,
              Date().timeIntervalSince(modDate) < ttl,
              let data = try? Data(contentsOf: fileURL),
              let image = PlatformImage(data: data) else {
            return nil
        }
        return image
    }

    private func storeMemory(_ image: PlatformImage, for url: URL) {
        memoryCache[url] = image
        touchMemory(url)
        while memoryCache.count > maxMemoryEntries, let oldest = accessOrder.first {
            memoryCache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
    }

    private func touchMemory(_ url: URL) {
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
    }

    private func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
