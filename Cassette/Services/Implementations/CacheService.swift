// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import OSLog

// NOTE(v1.x): cache is currently populated only by manual downloads (Étape 6).
// Automatic stream-alongside-cache will use AVAssetResourceLoaderDelegate once the
// byte-range / seek-resumption complexity is addressed.
actor CacheService: CacheServiceProtocol {
    private let modelContainer: ModelContainer
    private let cacheDirectory: URL

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = caches.appendingPathComponent("app.cassette/audio", isDirectory: true)
    }

    // MARK: - Lookup

    func cachedURL(forSongId songId: String, serverId: UUID) async -> URL? {
        let now = Date()
        let filePath: String? = await MainActor.run {
            let context = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<CachedTrack>(
                predicate: #Predicate { $0.songId == songId }
            )
            descriptor.fetchLimit = 1
            let track = (try? context.fetch(descriptor))?
                .first { $0.serverId == serverId && $0.expiresAt > now }
            return track?.filePath
        }
        guard let filePath else { return nil }
        let url = cacheDirectory.appendingPathComponent(filePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Stale DB record — clean up asynchronously.
            await invalidate(songId: songId, serverId: serverId)
            return nil
        }
        return url
    }

    // MARK: - Store

    func store(
        data: Data,
        forSongId songId: String,
        serverId: UUID,
        mimeType: String,
        ttl: TimeInterval
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let ext = mimeType.components(separatedBy: "/").last ?? "mp3"
        let filename = "\(serverId.uuidString)-\(songId).\(ext)"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)

        let fileSize = Int64(data.count)
        let now = Date()
        // "Until cache is full" is represented as .greatestFiniteMagnitude; clamp to distantFuture
        // to avoid overflow when computing a Date from an enormous TimeInterval.
        let expiresAt = ttl >= .greatestFiniteMagnitude ? Date.distantFuture : now.addingTimeInterval(ttl)

        await MainActor.run {
            let context = ModelContext(modelContainer)
            context.insert(CachedTrack(
                songId: songId,
                serverId: serverId,
                filePath: filename,
                fileSize: fileSize,
                mimeType: mimeType,
                cachedAt: now,
                expiresAt: expiresAt,
                lastAccessedAt: now
            ))
            try? context.save()
        }

        Logger.cache.info("Stored '\(songId, privacy: .public)' (\(fileSize) bytes, expires \(expiresAt, privacy: .public))")
        return fileURL
    }

    // MARK: - LRU touch

    func touch(songId: String, serverId: UUID) async {
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<CachedTrack>(
                predicate: #Predicate { $0.songId == songId }
            )
            guard let track = (try? context.fetch(descriptor))?.first(where: { $0.serverId == serverId })
            else { return }
            track.lastAccessedAt = Date()
            try? context.save()
        }
    }

    // MARK: - Eviction

    func evictExpired() async {
        let now = Date()
        let paths: [String] = await MainActor.run {
            let context = ModelContext(modelContainer)
            guard let tracks = try? context.fetch(FetchDescriptor<CachedTrack>()) else { return [] }
            let expired = tracks.filter { $0.expiresAt <= now }
            let paths = expired.map(\.filePath)
            expired.forEach { context.delete($0) }
            try? context.save()
            if !paths.isEmpty {
                Logger.cache.info("Evicted \(paths.count) expired track(s).")
            }
            return paths
        }
        paths.forEach { deleteFile(named: $0) }
    }

    func evictLRU(toFitQuota quotaBytes: Int64) async {
        let paths: [String] = await MainActor.run {
            let context = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<CachedTrack>(
                sortBy: [SortDescriptor(\.lastAccessedAt, order: .forward)]
            )
            guard let tracks = try? context.fetch(descriptor) else { return [] }

            let total = tracks.reduce(0) { $0 + $1.fileSize }
            guard total > quotaBytes else { return [] }

            var freed: Int64 = 0
            let target = total - quotaBytes
            var paths: [String] = []
            for track in tracks {
                guard freed < target else { break }
                freed += track.fileSize
                paths.append(track.filePath)
                context.delete(track)
            }
            try? context.save()
            Logger.cache.info("LRU eviction freed \(freed) bytes (\(paths.count) track(s)).")
            return paths
        }
        paths.forEach { deleteFile(named: $0) }
    }

    func invalidate(songId: String, serverId: UUID) async {
        let path: String? = await MainActor.run {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<CachedTrack>(
                predicate: #Predicate { $0.songId == songId }
            )
            guard let track = (try? context.fetch(descriptor))?.first(where: { $0.serverId == serverId })
            else { return nil }
            let path = track.filePath
            context.delete(track)
            try? context.save()
            return path
        }
        if let path { deleteFile(named: path) }
    }

    func clearAll() async {
        let paths: [String] = await MainActor.run {
            let context = ModelContext(modelContainer)
            guard let tracks = try? context.fetch(FetchDescriptor<CachedTrack>()) else { return [] }
            let paths = tracks.map(\.filePath)
            tracks.forEach { context.delete($0) }
            try? context.save()
            return paths
        }
        paths.forEach { deleteFile(named: $0) }
        Logger.cache.info("Cache cleared (\(paths.count) track(s) removed).")
    }

    // MARK: - Size

    var usedBytes: Int64 {
        get async {
            await MainActor.run {
                let context = ModelContext(modelContainer)
                guard let tracks = try? context.fetch(FetchDescriptor<CachedTrack>()) else { return 0 }
                return tracks.reduce(0) { $0 + $1.fileSize }
            }
        }
    }

    // MARK: - Disk helper

    private func deleteFile(named filename: String) {
        let url = cacheDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.cache.warning("Failed to delete cached file '\(filename, privacy: .public)': \(error, privacy: .public)")
        }
    }
}
