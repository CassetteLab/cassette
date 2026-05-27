// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import ImageIO
import OSLog
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - ArtworkTier

/// Named decode resolution tier for cover art.
///
/// Tier determines both the pixel dimension passed to CGImageSourceCreateThumbnailAtIndex
/// and the disk/RAM cache key suffix (`id@thumb`, `id@hero`).
nonisolated enum ArtworkTier: String, Sendable {
    /// 240 px — list rows, grid cells, queue rows, mini player, Wrapped cards.
    case thumb
    /// 1200 px — detail view heroes, full-player cover, lock screen artwork.
    case hero

    var decodePixels: Int {
        switch self {
        case .thumb: return 240
        case .hero: return 1200
        }
    }
}

// MARK: - CoverFetchGate

/// Limits concurrent server cover fetches so they cannot saturate the TCP connection pool
/// shared with the active audio stream. Uses a continuation-based semaphore so callers
/// are suspended (not blocked) while waiting for a slot.
private actor CoverFetchGate {
    private let limit: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit; available = limit }

    func acquire() async {
        if available > 0 { available -= 1; return }
        Logger.artworkCache.debug("[NET-COVER] gate: queued (limit=\(self.limit) busy, waiters=\(self.waiters.count + 1))")
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
            // available unchanged — slot transferred directly to the waiter
        } else {
            available += 1
        }
    }
}

// MARK: - ArtworkImageCache

/// Shared in-memory cache for cover art PlatformImages, keyed by `"\(coverArtId)@\(tier)"`.
///
/// Two decode tiers keep memory and decode cost proportional to display context:
///   • thumb (240 px) — list rows, grid cells, Wrapped cards, mini player
///   • hero  (1200 px) — detail view heroes, full-player cover, lock screen artwork
///
/// Both tiers for the same id can coexist in RAM. LRU eviction is unified across tiers;
/// maxEntries is sized to accommodate ~100 thumb + ~10 hero images.
///
/// Resolution order per tier: RAM → disk (`id@tier`) → server fetch + persist to `id@tier`.
///
/// Legacy plain-`id` files (full-res JPEGs written by pre-tier builds) are never read;
/// decoding them takes ~1100ms/file and starves the audio decode thread. They are cleaned
/// up on launch by AppContainer.sweepLegacyCoverArtFiles.
@MainActor
@Observable
final class ArtworkImageCache {
    private var cache: [String: PlatformImage] = [:]
    private var accessOrder: [String] = []
    private let maxEntries = 110

    private let downloadService: any DownloadServiceProtocol
    private let libraryService: any LibraryServiceProtocol
    private let session: URLSession
    // Caps in-flight server cover fetches to prevent saturating the TCP connection pool.
    private let fetchGate = CoverFetchGate(limit: 4)

    init(downloadService: any DownloadServiceProtocol, libraryService: any LibraryServiceProtocol) {
        self.downloadService = downloadService
        self.libraryService = libraryService
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Returns the cached image for the given tier synchronously, or nil if not yet loaded.
    /// Does not trigger a fetch — call load(coverArtId:tier:) for that.
    func cached(for coverArtId: String?, tier: ArtworkTier = .thumb) -> PlatformImage? {
        guard let coverArtId else { return nil }
        let key = cacheKey(id: coverArtId, tier: tier)
        guard let image = cache[key] else { return nil }
        touch(key)
        return image
    }

    /// Read-only sync lookup — no LRU touch, no fetch.
    func cachedImage(for id: String, tier: ArtworkTier = .thumb) -> PlatformImage? {
        cache[cacheKey(id: id, tier: tier)]
    }

    /// Returns the image from cache if available; otherwise fetches from disk or server.
    /// The `tier` determines both decode resolution and which disk/RAM bucket is checked.
    @discardableResult
    func load(coverArtId: String?, tier: ArtworkTier = .thumb) async -> PlatformImage? {
        guard let coverArtId else { return nil }

        let key = cacheKey(id: coverArtId, tier: tier)
        let maxDim = tier.decodePixels

        // 1. RAM hit.
        if let hit = cache[key] {
            touch(key)
            return hit
        }

        // 2. Disk hit — tiered file only (`{id}@thumb` / `{id}@hero`).
        //    Legacy untagged files (`{id}` with no suffix, full-res JPEGs written by
        //    pre-tier builds) are deliberately not read: decoding a 2000×2000 JPEG at
        //    240px takes ~1100ms even on a background thread, starving the audio decode
        //    thread and causing audible crackling. If the tiered file doesn't exist,
        //    skip directly to the network fetch (step 3). Untagged legacy files are
        //    cleaned up on launch by AppContainer.sweepLegacyCoverArtFiles.
        let tieredDiskId = "\(coverArtId)@\(tier.rawValue)"
        if let localURL = await downloadService.localCoverArtURL(forId: tieredDiskId) {
            let image = await Task.detached(priority: .userInitiated) {
                let diskStart = CFAbsoluteTimeGetCurrent()
                guard let data = try? Data(contentsOf: localURL) else { return nil as PlatformImage? }
                let diskMs = Int((CFAbsoluteTimeGetCurrent() - diskStart) * 1000)
                let decodeStart = CFAbsoluteTimeGetCurrent()
                let image = ArtworkImageCache.thumbnailImage(from: data, maxDimension: maxDim)
                let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)
                if diskMs + decodeMs > 50 {
                    Logger.artworkCache.warning("[DISK-SLOW] id=\(coverArtId, privacy: .public) tier=\(tier.rawValue, privacy: .public) disk=\(diskMs)ms decode=\(decodeMs)ms (background thread)")
                } else {
                    Logger.artworkCache.debug("[DISK] id=\(coverArtId, privacy: .public) tier=\(tier.rawValue, privacy: .public) disk=\(diskMs)ms decode=\(decodeMs)ms")
                }
                return image
            }.value
            if let image {
                store(image: image, forKey: key)
                Logger.artworkCache.debug("ArtworkImageCache: disk hit \(coverArtId, privacy: .public) tier=\(tier.rawValue, privacy: .public) (\(self.cache.count, privacy: .public)/\(self.maxEntries, privacy: .public))")
                return image
            }
        }

        // 3. Server fetch — gated to cap concurrency and protect the audio buffer.
        await fetchGate.acquire()
        Logger.artworkCache.debug("[NET-COVER] start id=\(coverArtId, privacy: .public) tier=\(tier.rawValue, privacy: .public) size=\(maxDim)px")
        let result = await serverFetch(coverArtId: coverArtId, key: key, tier: tier)
        await fetchGate.release()
        return result
    }

    private func serverFetch(coverArtId: String, key: String, tier: ArtworkTier) async -> PlatformImage? {
        let maxDim = tier.decodePixels
        guard let serverURL = await libraryService.coverArtURL(id: coverArtId, size: maxDim) else { return nil }
        let t0 = Date()
        guard let (data, _) = try? await session.data(from: serverURL) else {
            Logger.artworkCache.warning("[NET-COVER] failed id=\(coverArtId, privacy: .public) duration=\(Int(Date().timeIntervalSince(t0) * 1000))ms")
            return nil
        }
        // Decode off main thread — handles high-res outliers the server may return.
        let image = await Task.detached(priority: .userInitiated) {
            ArtworkImageCache.thumbnailImage(from: data, maxDimension: maxDim)
        }.value
        guard let image else {
            Logger.artworkCache.warning("[NET-COVER] failed (decode) id=\(coverArtId, privacy: .public) duration=\(Int(Date().timeIntervalSince(t0) * 1000))ms")
            return nil
        }
        Logger.artworkCache.debug("[NET-COVER] done id=\(coverArtId, privacy: .public) tier=\(tier.rawValue, privacy: .public) duration=\(Int(Date().timeIntervalSince(t0) * 1000))ms bytes=\(data.count, privacy: .public)")
        store(image: image, forKey: key)
        // Persist using the tier-suffixed filename so each tier has its own disk file.
        await downloadService.persistCover(data, forId: "\(coverArtId)@\(tier.rawValue)")
        return image
    }

    func invalidate(for coverArtId: String) async {
        // Remove both tier RAM entries and their disk files, plus the plain-id offline file.
        for key in ["\(coverArtId)@thumb", "\(coverArtId)@hero", coverArtId] {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            await downloadService.removeCover(forId: key)
        }
        Logger.artworkCache.debug("ArtworkImageCache: invalidated \(coverArtId, privacy: .public) (RAM + disk)")
    }

    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Private

    private func cacheKey(id: String, tier: ArtworkTier) -> String {
        "\(id)@\(tier.rawValue)"
    }

    private func store(image: PlatformImage, forKey key: String) {
        cache[key] = image
        touch(key)
        while cache.count > maxEntries, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
    }

    private func touch(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    /// Decodes `data` using `CGImageSourceCreateThumbnailAtIndex`, which only reads the DCT
    /// data needed for the target resolution — dramatically faster than full decode for
    /// high-res covers. Falls back to `PlatformImage(data:)` if ImageIO cannot produce
    /// a thumbnail (e.g. unsupported format).
    ///
    /// `nonisolated` so it is callable from `Task.detached` without hopping to MainActor.
    private nonisolated static func thumbnailImage(from data: Data, maxDimension: Int) -> PlatformImage? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return PlatformImage(data: data)
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        #endif
    }
}
