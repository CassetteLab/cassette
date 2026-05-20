// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared in-memory cache for cover art PlatformImages, keyed by coverArtId.
///
/// Follows the DominantColorExtractor pattern (@MainActor @Observable) so it is
/// injectable into the SwiftUI environment and readable synchronously from any
/// MainActor context (context menu previews, NowPlayingInfoCenter updates).
///
/// Resolution order: RAM → disk (Documents/coverarts/) → server fetch + persist to disk.
/// All paths — downloads and streamed covers — share the same disk directory, so a
/// cover fetched during streaming is available instantly on the next cold start.
/// LRU eviction keeps the RAM cache under maxEntries to prevent memory pressure.
@MainActor
@Observable
final class ArtworkImageCache {
    private var cache: [String: PlatformImage] = [:]
    private var accessOrder: [String] = []
    private let maxEntries = 50

    private let downloadService: any DownloadServiceProtocol
    private let libraryService: any LibraryServiceProtocol
    private let session: URLSession

    init(downloadService: any DownloadServiceProtocol, libraryService: any LibraryServiceProtocol) {
        self.downloadService = downloadService
        self.libraryService = libraryService
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Returns the cached image synchronously, or nil if not yet loaded.
    /// Does not trigger a fetch — call load(coverArtId:) for that.
    func cached(for coverArtId: String?) -> PlatformImage? {
        guard let coverArtId else { return nil }
        guard let image = cache[coverArtId] else { return nil }
        touch(coverArtId)
        return image
    }

    /// Returns the image from cache if available; otherwise fetches from disk
    /// or server, populates the RAM cache, and (on server fetch) persists to disk.
    @discardableResult
    func load(coverArtId: String?) async -> PlatformImage? {
        guard let coverArtId else { return nil }

        // 1. RAM hit.
        if let hit = cache[coverArtId] {
            touch(coverArtId)
            return hit
        }

        // 2. Disk hit (downloads or previously-persisted streaming covers).
        if let localURL = await downloadService.localCoverArtURL(forId: coverArtId),
           let data = try? Data(contentsOf: localURL),
           let image = PlatformImage(data: data) {
            store(image: image, for: coverArtId)
            Logger.artworkCache.debug("ArtworkImageCache: disk hit \(coverArtId, privacy: .public) (\(self.cache.count, privacy: .public)/\(self.maxEntries, privacy: .public))")
            return image
        }

        // 3. Server fetch → RAM + disk persist.
        guard let serverURL = await libraryService.coverArtURL(id: coverArtId, size: 600) else { return nil }
        guard let (data, _) = try? await session.data(from: serverURL),
              let image = PlatformImage(data: data) else {
            Logger.artworkCache.warning("ArtworkImageCache: failed to fetch \(coverArtId, privacy: .public) from server")
            return nil
        }
        store(image: image, for: coverArtId)
        await downloadService.persistCover(data, forId: coverArtId)
        Logger.artworkCache.debug("ArtworkImageCache: server fetch + persisted \(coverArtId, privacy: .public) (\(self.cache.count, privacy: .public)/\(self.maxEntries, privacy: .public))")
        return image
    }

    func invalidate(for coverArtId: String) async {
        cache.removeValue(forKey: coverArtId)
        accessOrder.removeAll { $0 == coverArtId }
        await downloadService.removeCover(forId: coverArtId)
        Logger.artworkCache.debug("ArtworkImageCache: invalidated \(coverArtId, privacy: .public) (RAM + disk)")
    }

    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Private

    private func store(image: PlatformImage, for coverArtId: String) {
        cache[coverArtId] = image
        touch(coverArtId)
        while cache.count > maxEntries, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
    }

    private func touch(_ coverArtId: String) {
        accessOrder.removeAll { $0 == coverArtId }
        accessOrder.append(coverArtId)
    }
}
