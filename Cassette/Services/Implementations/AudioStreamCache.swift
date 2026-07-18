// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import OSLog

/// Streaming cache for recently-played tracks. Holds a sliding window of the N most-recently-cached tracks.
/// FIFO eviction: when count exceeds the limit, the oldest by `cachedAt` is removed (file + record).
///
/// Caches AUDIO BYTES ONLY. It holds no library metadata — no albums, artists, playlists or search
/// results — and the app has no metadata cache at all: LibraryService goes to the server on every call.
/// Nothing here makes the library browsable offline; only the downloads store does.
///
/// Distinct from DownloadService:
/// - DownloadService → permanent, user-explicit, never auto-evicted, lives in Documents/.
/// - AudioStreamCache → transient, automatic, evicted by FIFO, lives in Caches/.
///
/// Populated via the streaming hook in PlayerService (phase 2). MediaResolver reads from this cache
/// between permanent downloads and remote streaming.
actor AudioStreamCache: AudioStreamCacheProtocol {
    private let modelContainer: ModelContainer
    private let cacheDirectory: URL
    private(set) var maxTracks: Int

    nonisolated static let defaultMaxTracks: Int = 10
    nonisolated static let minMaxTracks: Int = 1
    nonisolated static let maxMaxTracks: Int = 10

    init(modelContainer: ModelContainer, maxTracks: Int = AudioStreamCache.defaultMaxTracks) {
        self.modelContainer = modelContainer
        self.maxTracks = max(Self.minMaxTracks, min(Self.maxMaxTracks, maxTracks))

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = caches.appendingPathComponent("app.cassette/audio", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.cache.debug("AudioStreamCache: failed to create cache directory — \(error)")
        }
    }

    // MARK: - Configuration

    /// Updates the maximum number of tracks held in cache. Triggers FIFO eviction if count exceeds
    /// the new limit. Range is clamped to [1, 10].
    func setMaxTracks(_ value: Int) async {
        maxTracks = max(Self.minMaxTracks, min(Self.maxMaxTracks, value))
        await evictToFitLimit()
    }

    // MARK: - Lookup

    func cachedURL(forSongId songId: String, serverId: UUID) async -> URL? {
        let entry: (filePath: String, fileSize: Int64)? = await MainActor.run {
            let context = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<CachedTrack>(predicate: #Predicate { $0.songId == songId })
            descriptor.fetchLimit = 1
            let tracks = (try? context.fetch(descriptor)) ?? []
            return tracks.first { $0.serverId == serverId }.map { ($0.filePath, $0.fileSize) }
        }
        guard let entry else { return nil }
        let url = cacheDirectory.appendingPathComponent(entry.filePath)
        // Self-healing covers missing, empty, and size-mismatched files — a partial or
        // corrupt cache file must fall through to stream, never reach the player.
        let diskSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard diskSize > 0, diskSize == entry.fileSize else {
            Logger.cache.warning("Cache record exists but file missing or invalid (disk \(diskSize) bytes, record \(entry.fileSize)): \(entry.filePath, privacy: .public)")
            await invalidate(songId: songId, serverId: serverId)
            return nil
        }
        return url
    }

    func touch(songId: String, serverId: UUID) async {
        // No-op now that LRU is removed. Kept for MediaResolver API stability (phase 5 removes it).
    }

    // MARK: - Storage

    /// Stores audio data in the cache. Upserts the SwiftData record, then runs FIFO eviction.
    func store(data: Data, forSongId songId: String, serverId: UUID, mimeType: String) async throws -> URL {
        let ext = audioExtension(mimeType: mimeType)
        let relativePath = "\(serverId.uuidString)-\(songId).\(ext)"
        let fileURL = cacheDirectory.appendingPathComponent(relativePath)

        try data.write(to: fileURL, options: .atomic)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? Int64(data.count)

        await MainActor.run {
            let context = ModelContext(modelContainer)
            let existing = (try? context.fetch(FetchDescriptor<CachedTrack>(predicate: #Predicate { $0.songId == songId })))?
                .first { $0.serverId == serverId }
            if let existing {
                existing.filePath = relativePath
                existing.fileSize = fileSize
                existing.mimeType = mimeType
                existing.cachedAt = Date()
            } else {
                context.insert(CachedTrack(
                    songId: songId,
                    serverId: serverId,
                    filePath: relativePath,
                    fileSize: fileSize,
                    mimeType: mimeType
                ))
            }
            do {
                try context.save()
            } catch {
                Logger.cache.debug("AudioStreamCache: store save failed — \(error)")
            }
        }

        await evictToFitLimit()
        Logger.cache.info("Cached '\(songId, privacy: .public)' (\(fileSize) bytes, \(mimeType, privacy: .public))")
        return fileURL
    }

    private func audioExtension(mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "audio/mpeg", "audio/mp3":          return "mp3"
        case "audio/flac", "audio/x-flac":       return "flac"
        case "audio/mp4", "audio/m4a",
             "audio/aac", "audio/x-aac":         return "m4a"
        case "audio/ogg":                         return "ogg"
        case "audio/opus":                        return "opus"
        case "audio/wav", "audio/x-wav":         return "wav"
        case "audio/aiff", "audio/x-aiff":       return "aiff"
        default:                                  return "bin"
        }
    }

    // MARK: - Eviction

    /// FIFO eviction: removes the oldest tracks (by cachedAt asc) until count <= maxTracks.
    private func evictToFitLimit() async {
        // Capture actor-isolated maxTracks before the synchronous MainActor closure.
        let limit = maxTracks

        let toEvict: [(filePath: String, recordId: UUID)] = await MainActor.run {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<CachedTrack>(sortBy: [SortDescriptor(\.cachedAt, order: .forward)])
            let allTracks = (try? context.fetch(descriptor)) ?? []
            let excess = allTracks.count - limit
            guard excess > 0 else { return [] }
            return allTracks.prefix(excess).map { ($0.filePath, $0.id) }
        }

        guard !toEvict.isEmpty else { return }

        for entry in toEvict {
            do {
                try FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(entry.filePath))
            } catch {
                Logger.cache.debug("AudioStreamCache: evict removeItem failed — \(error)")
            }
        }

        let recordIds = toEvict.map(\.recordId)
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let allTracks = (try? context.fetch(FetchDescriptor<CachedTrack>())) ?? []
            allTracks.filter { recordIds.contains($0.id) }.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                Logger.cache.debug("AudioStreamCache: evict save failed — \(error)")
            }
        }

        Logger.cache.info("Evicted \(toEvict.count) cache entries (FIFO, oldest first)")
    }

    /// Manually invalidates a single entry (file + record). No-op if not cached.
    func invalidate(songId: String, serverId: UUID) async {
        let filePath: String? = await MainActor.run {
            let context = ModelContext(modelContainer)
            let tracks = (try? context.fetch(FetchDescriptor<CachedTrack>(predicate: #Predicate { $0.songId == songId }))) ?? []
            return tracks.first { $0.serverId == serverId }?.filePath
        }
        if let filePath {
            do {
                try FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(filePath))
            } catch {
                Logger.cache.debug("AudioStreamCache: invalidate removeItem failed — \(error)")
            }
        }
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let tracks = (try? context.fetch(FetchDescriptor<CachedTrack>(predicate: #Predicate { $0.songId == songId }))) ?? []
            tracks.filter { $0.serverId == serverId }.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                Logger.cache.debug("AudioStreamCache: invalidate save failed — \(error)")
            }
        }
        Logger.cache.debug("Invalidated cache for '\(songId, privacy: .public)'")
    }

    /// Clears the entire cache (all servers).
    func clearAll() async {
        let allFilePaths: [String] = await MainActor.run {
            let context = ModelContext(modelContainer)
            let tracks = (try? context.fetch(FetchDescriptor<CachedTrack>())) ?? []
            return tracks.map(\.filePath)
        }
        for filePath in allFilePaths {
            do {
                try FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(filePath))
            } catch {
                Logger.cache.debug("AudioStreamCache: clearAll removeItem failed — \(error)")
            }
        }
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let tracks = (try? context.fetch(FetchDescriptor<CachedTrack>())) ?? []
            tracks.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                Logger.cache.debug("AudioStreamCache: clearAll tracks save failed — \(error)")
            }
        }
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let lyrics = (try? context.fetch(FetchDescriptor<CachedLyrics>())) ?? []
            lyrics.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                Logger.cache.debug("AudioStreamCache: clearAll lyrics save failed — \(error)")
            }
        }
        Logger.cache.info("Cleared all cache entries")
    }

    /// Clears all cache entries for a specific server (used at server switch in phase 6).
    func clearAllForServer(_ serverId: UUID) async {
        let filePaths: [String] = await MainActor.run {
            let context = ModelContext(modelContainer)
            let tracks = (try? context.fetch(FetchDescriptor<CachedTrack>())) ?? []
            return tracks.filter { $0.serverId == serverId }.map(\.filePath)
        }
        for filePath in filePaths {
            do {
                try FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(filePath))
            } catch {
                Logger.cache.debug("AudioStreamCache: clearAllForServer removeItem failed — \(error)")
            }
        }
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let tracks = (try? context.fetch(FetchDescriptor<CachedTrack>())) ?? []
            tracks.filter { $0.serverId == serverId }.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                Logger.cache.debug("AudioStreamCache: clearAllForServer tracks save failed — \(error)")
            }
        }
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let lyrics = (try? context.fetch(FetchDescriptor<CachedLyrics>())) ?? []
            lyrics.filter { $0.serverId == serverId }.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                Logger.cache.debug("AudioStreamCache: clearAllForServer lyrics save failed — \(error)")
            }
        }
        Logger.cache.info("Cleared cache for server \(serverId.uuidString)")
    }

    // MARK: - Reporting

    /// Total bytes used by all cached tracks. Used by Settings UI.
    var usedBytes: Int64 {
        get async {
            await MainActor.run {
                let context = ModelContext(modelContainer)
                let tracks = (try? context.fetch(FetchDescriptor<CachedTrack>())) ?? []
                return tracks.map(\.fileSize).reduce(0, +)
            }
        }
    }

    /// Number of cached tracks. Used by Settings UI.
    var trackCount: Int {
        get async {
            await MainActor.run {
                let context = ModelContext(modelContainer)
                let tracks = (try? context.fetch(FetchDescriptor<CachedTrack>())) ?? []
                return tracks.count
            }
        }
    }
}
