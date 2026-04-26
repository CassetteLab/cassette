// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
/// URL resolution order: local downloaded file → server URL (credentials embedded
/// as query params by LibraryService, consistent with CoverArtView behaviour).
/// LRU eviction keeps the cache under maxEntries to prevent memory pressure.
@MainActor
@Observable
final class ArtworkImageCache {
    private var cache: [String: PlatformImage] = [:]
    private var accessOrder: [String] = []
    private let maxEntries = 50

    private let downloadService: any DownloadServiceProtocol
    private let libraryService: any LibraryServiceProtocol

    init(downloadService: any DownloadServiceProtocol, libraryService: any LibraryServiceProtocol) {
        self.downloadService = downloadService
        self.libraryService = libraryService
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

    /// Returns the image from cache if available; otherwise fetches from local
    /// disk or server, caches the result, and returns it.
    @discardableResult
    func load(coverArtId: String?) async -> PlatformImage? {
        guard let coverArtId else { return nil }
        if let hit = cache[coverArtId] {
            touch(coverArtId)
            return hit
        }
        guard let url = await resolveURL(for: coverArtId) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = PlatformImage(data: data) else {
            Logger.player.warning("ArtworkImageCache: failed to load image for \(coverArtId)")
            return nil
        }
        store(image: image, for: coverArtId)
        Logger.player.debug("ArtworkImageCache: cached \(coverArtId) (\(self.cache.count)/\(self.maxEntries))")
        return image
    }

    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Private

    private func resolveURL(for coverArtId: String) async -> URL? {
        if let localURL = await downloadService.localCoverArtURL(forId: coverArtId) {
            return localURL
        }
        return await libraryService.coverArtURL(id: coverArtId, size: 300)
    }

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
