// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import CoreGraphics
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
nonisolated enum ArtworkTier: String, Sendable, CaseIterable {
    /// 240 px — list rows, queue rows, mini player, small avatars.
    case thumb
    /// 600 px — album and playlist grid cells.
    case grid
    /// 1200 px — detail view heroes, full-player cover, lock screen artwork.
    case hero

    /// `thumb` used to cover grid cells too, and that was the bug: a 180pt cell on a @3x screen
    /// needs 540 px, and 240 was both decoded AND requested from the server, so the blur came
    /// down the wire. A 44pt row needs 132 px, so giving both the same tier meant either blurry
    /// grids or 25× the memory every list row deserves.
    var decodePixels: Int {
        switch self {
        case .thumb: return 240
        case .grid: return 600
        case .hero: return 1200
        }
    }

    /// Decoded bytes once in RAM: 4 bytes per pixel, squared.
    var approximateBytes: Int {
        decodePixels * decodePixels * 4
    }

    /// Tiers holding strictly more pixels than this one, cheapest first.
    ///
    /// Used to satisfy a request from a bigger image already in hand instead of decoding the
    /// same file again. Cheapest-first matters: a `thumb` should ride a `grid`, not a `hero`.
    /// Only strictly larger tiers qualify — never upscale, which is what made grid cells blurry
    /// when one tier served both rows and cells. The relation is strictly increasing, so a chain
    /// of waits (thumb on grid on hero) can never cycle.
    var largerTiers: [ArtworkTier] {
        Self.allCases
            .filter { $0.decodePixels > decodePixels }
            .sorted { $0.decodePixels < $1.decodePixels }
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
/// Three decode tiers keep memory and decode cost proportional to display context:
///   • thumb (240 px) — list rows, Wrapped cards, mini player, small avatars
///   • grid  (600 px) — album and playlist grid cells
///   • hero  (1200 px) — detail view heroes, full-player cover, lock screen artwork
///
/// Every tier for the same id can coexist in RAM. LRU eviction is unified across tiers and
/// bounded in bytes (`costLimit`), not in entries: a hero weighs 25x a thumb, so a count
/// bounds nothing.
///
/// Resolution order per tier: RAM → disk (`id@tier`) → server fetch + persist to `id@tier`.
///
/// The tiered `load` never reads plain-`id` files: pre-tier builds wrote full-res JPEGs under that
/// name and decoding one takes ~1100ms, starving the audio decode thread. The same name is
/// also used for the covers saved alongside offline downloads, which must be left alone —
/// `localImage` reads those only as an offline fallback for `CoverArtView`.
@MainActor
@Observable
final class ArtworkImageCache {
    private var cache: [String: PlatformImage] = [:]
    private var accessOrder: [String] = []
    private var costs: [String: Int] = [:]
    private var totalCost = 0

    /// Bounded in bytes, not in entries. A count cannot bound anything here: a hero weighs 25×
    /// a thumb, so the old limit of 110 entries allowed anything between 24 MB (all thumb) and
    /// 604 MB (all hero) — and this process also runs an audio engine, which iOS is far less
    /// forgiving about.
    private let costLimit = 120 * 1024 * 1024

    private let downloadService: any DownloadServiceProtocol
    private let libraryService: any LibraryServiceProtocol
    private let session: URLSession
    // Caps in-flight server cover fetches to prevent saturating the TCP connection pool.
    private let fetchGate = CoverFetchGate(limit: 4)

    /// Work already running per cache key, so concurrent callers for the same cover share one
    /// disk read and one server fetch instead of each doing the whole job.
    ///
    /// `load` has suspension points before anything is stored, so two callers arriving for the
    /// same key both cleared the RAM check and both went to disk and to the network — logs showed
    /// the same cover downloaded twice and burning two of the four `fetchGate` slots. The lookup
    /// and the insert below both run on the main actor with no `await` between them, so the
    /// second caller always sees the first one's task.
    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]

    // MARK: - Revalidation
    /// Per-cover `Last-Modified` + last-checked, so a cached cover is re-verified on a slow cadence.
    private let revalidationStore: CoverRevalidationStore
    /// Cover ids whose revalidation is in flight, so the tiers of one id don't each HEAD it.
    private var revalidating: Set<String> = []
    /// Ids whose revalidation failed this run (offline / error). Skipped until relaunch so an
    /// offline session doesn't fire a HEAD per cover on every scroll.
    private var revalidationDeferred: Set<String> = []

    init(
        downloadService: any DownloadServiceProtocol,
        libraryService: any LibraryServiceProtocol,
        revalidationStore: CoverRevalidationStore = CoverRevalidationStore()
    ) {
        self.downloadService = downloadService
        self.libraryService = libraryService
        self.revalidationStore = revalidationStore
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

    /// Read-only sync lookup for an exact tier — no LRU touch, no fetch.
    func cachedImage(for id: String, tier: ArtworkTier) -> PlatformImage? {
        cache[cacheKey(id: id, tier: tier)]
    }

    /// Best available image for a transition or placeholder while the requested tier loads.
    func cachedImage(for id: String) -> PlatformImage? {
        for tier in ArtworkTier.allCases.reversed() {
            if let image = cachedImage(for: id, tier: tier) { return image }
        }
        return nil
    }

    /// On-disk fallback, including other tiers when the requested size isn't cached.
    /// Never fetches or stores a lower-resolution fallback under the requested tier's key.
    func localImage(for id: String, tier: ArtworkTier) async -> PlatformImage? {
        // The untagged `id` file goes LAST: pre-tier builds and offline downloads wrote full-res
        // JPEGs under that name, and decoding one takes ~1100ms, starving the audio decode thread.
        // Any tiered file is smaller and decodes in a fraction of that, so probe them all first.
        let diskIds = [cacheKey(id: id, tier: tier)]
            + ArtworkTier.allCases.reversed().filter { $0 != tier }.map { cacheKey(id: id, tier: $0) }
            + [id]
        for diskId in diskIds {
            guard !Task.isCancelled else { return nil }
            guard let url = await downloadService.localCoverArtURL(forId: diskId) else { continue }
            let image = await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url) else { return nil as PlatformImage? }
                return Self.thumbnailImage(from: data, maxDimension: tier.decodePixels)
            }.value
            guard !Task.isCancelled else { return nil }
            if let image { return image }
        }
        return nil
    }

    /// Returns the image from cache if available; otherwise fetches from disk or server.
    /// The `tier` determines both decode resolution and which disk/RAM bucket is checked.
    @discardableResult
    func load(coverArtId: String?, tier: ArtworkTier = .thumb) async -> PlatformImage? {
        guard let coverArtId else { return nil }

        let key = cacheKey(id: coverArtId, tier: tier)

        // 1. RAM hit.
        if let hit = cache[key] {
            touch(key)
            revalidateIfDue(coverArtId: coverArtId, tier: tier)
            return hit
        }

        // 1b. Someone is already fetching this exact key — await their result.
        if let running = inFlight[key] {
            return await running.value
        }

        // Not a child task: cancelling the caller that happened to create it must not cancel
        // work the other waiters are relying on.
        let task = makeLoadTask(coverArtId: coverArtId, key: key, tier: tier)
        inFlight[key] = task
        let image = await task.value
        // Only the creator clears the entry; waiters never touch the registry.
        inFlight.removeValue(forKey: key)
        return image
    }

    /// Picks how to satisfy a key that is not in RAM and not already being fetched.
    ///
    /// Only the RAM case is decided here. A larger tier already decoded in memory is always
    /// cheaper to resample than to read and decode the file again, with no suspension in
    /// between, so it is free of the trap below.
    ///
    /// Riding a larger tier that is still *in flight* is deliberately NOT done here: our own
    /// tiered file may be sitting on disk (2 ms) while the larger one still has to come down
    /// from the server (200 ms+), and waiting would be slower than the status quo. That case is
    /// reconsidered inside `fetchUncached`, once our own file is known to be missing.
    private func makeLoadTask(coverArtId: String, key: String, tier: ArtworkTier) -> Task<PlatformImage?, Never> {
        if let (big, larger) = largerTierInRAM(coverArtId: coverArtId, than: tier) {
            return Task { [weak self] in
                guard let self else { return nil as PlatformImage? }
                if let small = await self.reuse(big, from: larger, for: key, coverArtId: coverArtId, tier: tier) {
                    return small
                }
                return await self.fetchUncached(coverArtId: coverArtId, key: key, tier: tier)
            }
        }

        return Task { [weak self] in
            guard let self else { return nil as PlatformImage? }
            return await self.fetchUncached(coverArtId: coverArtId, key: key, tier: tier)
        }
    }

    /// Cheapest tier above `tier` whose image is decoded in RAM, touched so it is not evicted
    /// from under us.
    private func largerTierInRAM(coverArtId: String, than tier: ArtworkTier) -> (PlatformImage, ArtworkTier)? {
        for larger in tier.largerTiers {
            let largerKey = cacheKey(id: coverArtId, tier: larger)
            if let big = cache[largerKey] {
                touch(largerKey)
                return (big, larger)
            }
        }
        return nil
    }

    /// Cheapest tier above `tier` already being fetched. Worth waiting for only when the
    /// alternative is a server round trip.
    private func largerTierInFlight(coverArtId: String, than tier: ArtworkTier) -> (Task<PlatformImage?, Never>, ArtworkTier)? {
        for larger in tier.largerTiers {
            if let running = inFlight[cacheKey(id: coverArtId, tier: larger)] {
                return (running, larger)
            }
        }
        return nil
    }

    /// Downscales an image from a larger tier and stores it under `key`. Nil if it cannot be
    /// resampled, which sends the caller back to a normal fetch.
    private func reuse(
        _ big: PlatformImage,
        from larger: ArtworkTier,
        for key: String,
        coverArtId: String,
        tier: ArtworkTier
    ) async -> PlatformImage? {
        let maxDim = tier.decodePixels
        let t0 = CFAbsoluteTimeGetCurrent()
        // Off the main actor: resampling a 1200 px image is milliseconds, but this runs in a
        // process that also feeds an audio engine.
        let small = await Task.detached(priority: .userInitiated) {
            ArtworkImageCache.downscaled(big, maxDimension: maxDim)
        }.value
        guard let small else { return nil }
        store(image: small, forKey: key)
        let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        Logger.artworkCache.debug("[REUSE] id=\(coverArtId, privacy: .public) tier=\(tier.rawValue, privacy: .public) from=\(larger.rawValue, privacy: .public) \(ms)ms (\(self.cache.count, privacy: .public) covers, \(self.totalCost / 1_048_576, privacy: .public) MB)")
        revalidateIfDue(coverArtId: coverArtId, tier: tier)
        return small
    }

    /// Disk then server, for a key proven absent from RAM. Always called through `inFlight`.
    private func fetchUncached(coverArtId: String, key: String, tier: ArtworkTier) async -> PlatformImage? {
        let maxDim = tier.decodePixels

        // 2. Disk hit — tiered file only (`{id}@thumb` / `{id}@hero`).
        //    Legacy untagged files (`{id}` with no suffix, full-res JPEGs written by
        //    pre-tier builds) are deliberately not read: decoding a 2000×2000 JPEG at
        //    240px takes ~1100ms even on a background thread, starving the audio decode
        //    thread and causing audible crackling. If the tiered file doesn't exist,
        //    skip directly to the network fetch (step 3). Note the untagged name is also
        //    what offline downloads use, so nothing here may delete it.
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
                Logger.artworkCache.debug("ArtworkImageCache: disk hit \(coverArtId, privacy: .public) tier=\(tier.rawValue, privacy: .public) (\(self.cache.count, privacy: .public) covers, \(self.totalCost / 1_048_576, privacy: .public) MB)")
                revalidateIfDue(coverArtId: coverArtId, tier: tier)
                return image
            }
        }

        // 2b. Our own file is missing, so the alternative is now a server round trip — and that
        //     is the point where a larger tier becomes worth reusing. One may have landed in RAM
        //     while we were hitting the disk, or still be on its way; either beats a download.
        if let (big, larger) = largerTierInRAM(coverArtId: coverArtId, than: tier),
           let small = await reuse(big, from: larger, for: key, coverArtId: coverArtId, tier: tier) {
            return small
        }
        if let (running, larger) = largerTierInFlight(coverArtId: coverArtId, than: tier),
           let big = await running.value,
           let small = await reuse(big, from: larger, for: key, coverArtId: coverArtId, tier: tier) {
            return small
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
        guard let (data, response) = try? await session.data(from: serverURL) else {
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
        // A fresh fetch already carries the current Last-Modified — record it as the baseline so we
        // don't waste a HEAD re-checking a cover we just downloaded.
        if let http = response as? HTTPURLResponse {
            revalidationStore.record(id: coverArtId, lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
        }
        return image
    }

    // MARK: - Revalidation

    /// Fires a background re-check of `coverArtId` when its TTL has lapsed. Non-blocking: the caller
    /// has already returned the cached image, so this is pure stale-while-revalidate — the view
    /// keeps the old cover until (and unless) a change is found.
    private func revalidateIfDue(coverArtId: String, tier: ArtworkTier) {
        guard !revalidating.contains(coverArtId),
              !revalidationDeferred.contains(coverArtId),
              revalidationStore.isDue(id: coverArtId) else { return }
        revalidating.insert(coverArtId)
        Task { await self.revalidate(coverArtId: coverArtId, tier: tier) }
    }

    private func revalidate(coverArtId: String, tier: ArtworkTier) async {
        defer { revalidating.remove(coverArtId) }
        guard let url = await libraryService.coverArtURL(id: coverArtId, size: tier.decodePixels) else { return }

        // HEAD reads the Last-Modified without transferring the image — Navidrome returns it on a
        // header-only response, so an unchanged cover costs a single round-trip and no bytes.
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            // Offline or errored — don't retry this cover until relaunch, so a scroll offline
            // doesn't fire a HEAD per row.
            revalidationDeferred.insert(coverArtId)
            return
        }

        let serverLM = http.value(forHTTPHeaderField: "Last-Modified")
        switch CoverRevalidationOutcome.decide(stored: revalidationStore.lastModified(for: coverArtId), server: serverLM) {
        case .baseline, .unchanged, .indeterminate:
            // Nothing to fetch — just record what the server told us and reset the timer.
            revalidationStore.record(id: coverArtId, lastModified: serverLM)
        case .changed:
            Logger.artworkCache.info("[REVAL] cover changed id=\(coverArtId, privacy: .public) — refetching")
            await refetchChangedCover(coverArtId: coverArtId, tier: tier, newLastModified: serverLM)
        }
    }

    /// Replaces every cached copy of a cover that changed on the server, then nudges the UI to
    /// re-read it. The tier that triggered the check is fetched now; the other tier is dropped so it
    /// re-fetches fresh on its next access.
    private func refetchChangedCover(coverArtId: String, tier: ArtworkTier, newLastModified: String?) async {
        // Drop stale copies of EVERY tier so nothing old survives. Iterating allCases rather
        // than a hand-written list is what stops a new tier from silently keeping stale covers.
        for staleTier in ArtworkTier.allCases {
            let staleKey = cacheKey(id: coverArtId, tier: staleTier)
            drop(staleKey)
            await downloadService.removeCover(forId: staleKey)
        }
        // Fetch the tier we were asked for; serverFetch re-records the baseline from its response.
        _ = await serverFetch(coverArtId: coverArtId, key: cacheKey(id: coverArtId, tier: tier), tier: tier)
        // Belt-and-braces in case the fetch response lacked the header.
        revalidationStore.record(id: coverArtId, lastModified: newLastModified)
        // CoverArtView reads the cache inside a `.task(id:)` keyed on this counter, so bumping it is
        // what makes the freshly-fetched image actually appear without the user leaving the screen.
        let key = "coverArtUploadVersion"
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }

    func invalidate(for coverArtId: String) async {
        // Every tier's RAM entry and disk file, plus the plain-id offline file.
        for key in ArtworkTier.allCases.map({ cacheKey(id: coverArtId, tier: $0) }) + [coverArtId] {
            drop(key)
            await downloadService.removeCover(forId: key)
        }
        Logger.artworkCache.debug("ArtworkImageCache: invalidated \(coverArtId, privacy: .public) (RAM + disk)")
    }

    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
        costs.removeAll()
        totalCost = 0
    }

    /// Drops every cached cover — memory and the re-fetchable tier files on disk — and forces
    /// the views to re-resolve.
    ///
    /// Covers captured alongside offline downloads (bare `{id}` files) are deliberately left
    /// alone: nothing re-creates them short of downloading the tracks again, so removing them
    /// would leave a downloaded album with no artwork in airplane mode. Returns the number of
    /// disk files removed.
    @discardableResult
    func clearAllCovers() async -> Int {
        clearCache()
        clearRevalidationMetadata()
        let removed = await downloadService.clearStreamingCovers()
        // Every CoverArtView folds this counter into its task id, so bumping it is what makes
        // already-visible artwork re-resolve rather than sit on a now-deleted image.
        let key = "coverArtUploadVersion"
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
        Logger.artworkCache.info("Artwork cache cleared — \(removed) cached file(s) removed.")
        return removed
    }

    /// Forgets all revalidation metadata. Called from the version-bump disk wipe so a fresh cache
    /// doesn't carry `Last-Modified` values describing images that were just deleted.
    func clearRevalidationMetadata() {
        revalidationStore.removeAll()
        revalidating.removeAll()
        revalidationDeferred.removeAll()
    }

    // MARK: - Private

    private func cacheKey(id: String, tier: ArtworkTier) -> String {
        "\(id)@\(tier.rawValue)"
    }

    private func store(image: PlatformImage, forKey key: String) {
        drop(key)
        cache[key] = image
        let cost = Self.bytes(of: image)
        costs[key] = cost
        totalCost += cost
        touch(key)

        // Never evict what was just stored, however large: a single oversized cover must not
        // empty the cache and then drop itself.
        while totalCost > costLimit, accessOrder.count > 1, let oldest = accessOrder.first {
            drop(oldest)
        }
    }

    /// Removes one entry and its cost. Every removal goes through here, so `totalCost` cannot
    /// drift away from what is actually held.
    private func drop(_ key: String) {
        guard cache.removeValue(forKey: key) != nil else {
            accessOrder.removeAll { $0 == key }
            return
        }
        totalCost -= costs.removeValue(forKey: key) ?? 0
        accessOrder.removeAll { $0 == key }
    }

    private static func bytes(of image: PlatformImage) -> Int {
        #if canImport(UIKit)
        guard let cg = image.cgImage else { return 0 }
        #else
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        #endif
        return cg.width * cg.height * 4
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
    /// Internal (not private) so `CoverArtView`'s local-base fallback decodes identically.
    /// Resamples an already-decoded image so its longest side is `maxDimension`.
    ///
    /// Nil when the image is already that small or smaller — there is nothing to gain and
    /// upscaling is never wanted — and nil on any failure, which sends the caller back to a
    /// normal decode rather than showing something soft.
    ///
    /// The result is the same pixel size a direct decode would have produced, so this cannot
    /// reintroduce the blur from one tier serving two sizes; only the resampling method differs
    /// (Core Graphics here, ImageIO's DCT scaling there).
    nonisolated static func downscaled(_ image: PlatformImage, maxDimension: Int) -> PlatformImage? {
        guard maxDimension > 0 else { return nil }
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return nil }
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #endif

        let longest = max(cgImage.width, cgImage.height)
        guard longest > maxDimension else { return nil }

        let scale = Double(maxDimension) / Double(longest)
        let width = max(1, Int((Double(cgImage.width) * scale).rounded()))
        let height = max(1, Int((Double(cgImage.height) * scale).rounded()))

        // sRGB and BGRA are forced rather than inherited: a source in an indexed, CMYK or
        // 16-bit space is not a valid CGContext target and would fail here.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }

        #if canImport(UIKit)
        return UIImage(cgImage: scaled)
        #else
        return NSImage(cgImage: scaled, size: NSSize(width: width, height: height))
        #endif
    }

    nonisolated static func thumbnailImage(from data: Data, maxDimension: Int) -> PlatformImage? {
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
