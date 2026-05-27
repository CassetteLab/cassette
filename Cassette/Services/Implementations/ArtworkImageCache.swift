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
    // Caps in-flight server cover fetches to prevent saturating the TCP connection pool
    // that the audio stream shares. 4 slots ≈ fast sequential loading; 2-connection limit
    // on the session ensures covers never hold more than 2 TCP connections to the same host.
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

    /// Returns the cached image synchronously, or nil if not yet loaded.
    /// Does not trigger a fetch — call load(coverArtId:) for that.
    func cached(for coverArtId: String?) -> PlatformImage? {
        guard let coverArtId else { return nil }
        guard let image = cache[coverArtId] else { return nil }
        touch(coverArtId)
        return image
    }

    /// Read-only sync lookup by id — no LRU touch, no fetch.
    func cachedImage(for id: String) -> PlatformImage? {
        cache[id]
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

        // 2. Disk hit — dispatch read + decode to a background thread so the main actor
        //    stays free. Previously these ran on main, causing ~25ms freeze per image.
        if let localURL = await downloadService.localCoverArtURL(forId: coverArtId) {
            let image = await Task.detached(priority: .userInitiated) {
                let diskStart = CFAbsoluteTimeGetCurrent()
                guard let data = try? Data(contentsOf: localURL) else { return nil as PlatformImage? }
                let diskMs = Int((CFAbsoluteTimeGetCurrent() - diskStart) * 1000)
                let decodeStart = CFAbsoluteTimeGetCurrent()
                let image = ArtworkImageCache.thumbnailImage(from: data, maxDimension: 600)
                let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)
                if diskMs + decodeMs > 50 {
                    Logger.artworkCache.warning("[DISK-SLOW] id=\(coverArtId, privacy: .public) disk=\(diskMs)ms decode=\(decodeMs)ms (background thread)")
                } else {
                    Logger.artworkCache.debug("[DISK] id=\(coverArtId, privacy: .public) disk=\(diskMs)ms decode=\(decodeMs)ms")
                }
                return image
            }.value
            if let image {
                store(image: image, for: coverArtId)
                Logger.artworkCache.debug("ArtworkImageCache: disk hit \(coverArtId, privacy: .public) (\(self.cache.count, privacy: .public)/\(self.maxEntries, privacy: .public))")
                return image
            }
        }

        // 3. Server fetch — gated to cap concurrency and protect the audio buffer.
        await fetchGate.acquire()
        Logger.artworkCache.debug("[NET-COVER] start id=\(coverArtId, privacy: .public)")
        let result = await serverFetch(coverArtId: coverArtId)
        await fetchGate.release()
        return result
    }

    private func serverFetch(coverArtId: String) async -> PlatformImage? {
        guard let serverURL = await libraryService.coverArtURL(id: coverArtId, size: 600) else { return nil }
        let t0 = Date()
        guard let (data, _) = try? await session.data(from: serverURL) else {
            Logger.artworkCache.warning("[NET-COVER] failed id=\(coverArtId, privacy: .public) duration=\(Int(Date().timeIntervalSince(t0) * 1000))ms")
            return nil
        }
        // Decode off main thread — handles high-res outliers the server may return.
        let image = await Task.detached(priority: .userInitiated) {
            ArtworkImageCache.thumbnailImage(from: data, maxDimension: 600)
        }.value
        guard let image else {
            Logger.artworkCache.warning("[NET-COVER] failed (decode) id=\(coverArtId, privacy: .public) duration=\(Int(Date().timeIntervalSince(t0) * 1000))ms")
            return nil
        }
        Logger.artworkCache.debug("[NET-COVER] done id=\(coverArtId, privacy: .public) duration=\(Int(Date().timeIntervalSince(t0) * 1000))ms bytes=\(data.count, privacy: .public)")
        store(image: image, for: coverArtId)
        await downloadService.persistCover(data, forId: coverArtId)
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
