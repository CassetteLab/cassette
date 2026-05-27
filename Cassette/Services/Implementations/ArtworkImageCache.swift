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

/// Shared in-memory cache for cover art PlatformImages, keyed by coverArtId + size tier.
///
/// Two decode tiers keep memory and decode cost proportional to display context:
///   • thumb  (targetPixelSize < 480) → decoded at 240 px  — list rows, grid cells
///   • full   (targetPixelSize ≥ 480) → decoded at 1200 px — full-player hero, macOS detail
///
/// Cache keys use the suffix "@thumb" / "@full" so both tiers can coexist in RAM for
/// the same coverArtId. LRU eviction is unified across tiers; maxEntries is sized to
/// accommodate ~100 thumb + ~10 full images without excessive memory pressure.
///
/// Resolution order per tier: RAM → disk (Documents/coverarts/) → server fetch + persist.
@MainActor
@Observable
final class ArtworkImageCache {
    private var cache: [String: PlatformImage] = [:]
    private var accessOrder: [String] = []
    private let maxEntries = 110

    private let downloadService: any DownloadServiceProtocol
    private let libraryService: any LibraryServiceProtocol
    private let session: URLSession
    private let fetchGate = CoverFetchGate(limit: 4)

    // Decode pixel dimensions per tier.
    private let thumbDecodePixels = 240
    private let fullDecodePixels = 1200
    // Threshold (in requested pixels) below which a request is served from the thumb tier.
    private let fullTierThreshold = 480

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

    /// Returns the thumb-tier cached image synchronously, or nil if not yet loaded.
    /// Does not trigger a fetch — call load(coverArtId:) for that.
    func cached(for coverArtId: String?) -> PlatformImage? {
        guard let coverArtId else { return nil }
        let key = thumbKey(coverArtId)
        guard let image = cache[key] else { return nil }
        touch(key)
        return image
    }

    /// Read-only sync lookup — no LRU touch, no fetch.
    /// Uses the thumb tier by default; pass `pixelSize ≥ 480` to look up the full tier.
    func cachedImage(for id: String, pixelSize: Int = 240) -> PlatformImage? {
        cache[cacheKey(id: id, pixelSize: pixelSize)]
    }

    /// Returns the image from cache if available; otherwise fetches from disk or server.
    /// `targetPixelSize` determines the decode resolution and cache tier:
    ///   < 480 → thumb tier (240 px decode) — suitable for list rows and grid cells.
    ///   ≥ 480 → full tier (1200 px decode) — suitable for full-player and detail views.
    @discardableResult
    func load(coverArtId: String?, targetPixelSize: Int = 240) async -> PlatformImage? {
        guard let coverArtId else { return nil }

        let key = cacheKey(id: coverArtId, pixelSize: targetPixelSize)
        let maxDim = decodePixels(for: targetPixelSize)

        // 1. RAM hit.
        if let hit = cache[key] {
            touch(key)
            return hit
        }

        // 2. Disk hit — dispatch read + decode to a background thread so the main actor
        //    stays free. Previously these ran on main, causing ~25ms freeze per image.
        if let localURL = await downloadService.localCoverArtURL(forId: coverArtId) {
            let image = await Task.detached(priority: .userInitiated) {
                let diskStart = CFAbsoluteTimeGetCurrent()
                guard let data = try? Data(contentsOf: localURL) else { return nil as PlatformImage? }
                let diskMs = Int((CFAbsoluteTimeGetCurrent() - diskStart) * 1000)
                let decodeStart = CFAbsoluteTimeGetCurrent()
                let image = ArtworkImageCache.thumbnailImage(from: data, maxDimension: maxDim)
                let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)
                if diskMs + decodeMs > 50 {
                    Logger.artworkCache.warning("[DISK-SLOW] id=\(coverArtId, privacy: .public) size=\(maxDim)px disk=\(diskMs)ms decode=\(decodeMs)ms (background thread)")
                } else {
                    Logger.artworkCache.debug("[DISK] id=\(coverArtId, privacy: .public) size=\(maxDim)px disk=\(diskMs)ms decode=\(decodeMs)ms")
                }
                return image
            }.value
            if let image {
                store(image: image, forKey: key)
                Logger.artworkCache.debug("ArtworkImageCache: disk hit \(coverArtId, privacy: .public) tier=\(key, privacy: .public) (\(self.cache.count, privacy: .public)/\(self.maxEntries, privacy: .public))")
                return image
            }
        }

        // 3. Server fetch — gated to cap concurrency and protect the audio buffer.
        await fetchGate.acquire()
        Logger.artworkCache.debug("[NET-COVER] start id=\(coverArtId, privacy: .public) size=\(maxDim)px")
        let result = await serverFetch(coverArtId: coverArtId, key: key, maxDim: maxDim)
        await fetchGate.release()
        return result
    }

    private func serverFetch(coverArtId: String, key: String, maxDim: Int) async -> PlatformImage? {
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
        Logger.artworkCache.debug("[NET-COVER] done id=\(coverArtId, privacy: .public) size=\(maxDim)px duration=\(Int(Date().timeIntervalSince(t0) * 1000))ms bytes=\(data.count, privacy: .public)")
        store(image: image, forKey: key)
        await downloadService.persistCover(data, forId: coverArtId)
        return image
    }

    func invalidate(for coverArtId: String) async {
        for tier in ["thumb", "full"] {
            let key = "\(coverArtId)@\(tier)"
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
        await downloadService.removeCover(forId: coverArtId)
        Logger.artworkCache.debug("ArtworkImageCache: invalidated \(coverArtId, privacy: .public) (RAM + disk)")
    }

    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Private

    private func thumbKey(_ id: String) -> String { "\(id)@thumb" }

    private func cacheKey(id: String, pixelSize: Int) -> String {
        pixelSize < fullTierThreshold ? "\(id)@thumb" : "\(id)@full"
    }

    private func decodePixels(for pixelSize: Int) -> Int {
        pixelSize < fullTierThreshold ? thumbDecodePixels : fullDecodePixels
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
