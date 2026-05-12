// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftData
import OSLog
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if os(iOS)
import WidgetKit
#endif

nonisolated enum WidgetSyncError: Error {
    case sharedContainerUnavailable
}

/// Keeps the App Group shared container in sync with recently played tracks,
/// pinned items, bridged cover art (JPG 600x600 80%), and dominant colors.
///
/// Called from PlayerService (track change), PinService (pin/unpin), and
/// CassetteApp (cold start). All writes are idempotent so duplicate triggers
/// from rapid skips are safe — the throttle on reloadTimelinesIfNeeded()
/// prevents WidgetCenter spam.
actor WidgetSyncService {
    private let dominantColorExtractor: DominantColorExtractor
    private let modelContainer: ModelContainer
    private let artworkCache: ArtworkImageCache
    /// Path to Documents/app.cassette/coverarts/ — same dir used by DownloadService.
    private let coversDirectory: URL
    private let serverState: ServerState

    private var lastReloadDate: Date?

    init(
        dominantColorExtractor: DominantColorExtractor,
        modelContainer: ModelContainer,
        artworkCache: ArtworkImageCache,
        coversDirectory: URL,
        serverState: ServerState
    ) {
        self.dominantColorExtractor = dominantColorExtractor
        self.modelContainer = modelContainer
        self.artworkCache = artworkCache
        self.coversDirectory = coversDirectory
        self.serverState = serverState
    }

    // MARK: - Public API (implemented in commits 3b / 3c)

    func onTrackStarted(_ song: DisplayableSong) async {}

    func syncPinned() async {}

    func syncDominantColors(forCoverArtIds ids: [String]) async {
        let allCached = await dominantColorExtractor.cachedColors()
        let filtered = allCached.filter { ids.contains($0.key) }
        guard !filtered.isEmpty else { return }
        SharedStorage.defaults.set(filtered, forKey: SharedStorageKey.dominantColors.rawValue)
        Logger.widget.debug("syncDominantColors: wrote \(filtered.count) colors to shared defaults")
    }

    func fullSync() async {}

    // MARK: - Cover art bridge

    /// Copies a cover from the app's local cache into the App Group shared container
    /// as a 600×600 JPG at 80% quality. Idempotent — no-op if the file already exists.
    func bridgeCoverArt(coverArtId: String) async throws {
        guard let sharedDir = SharedStorage.coverArtCacheDirectory else {
            throw WidgetSyncError.sharedContainerUnavailable
        }
        try SharedStorage.ensureDirectoriesExist()

        let sharedURL = sharedDir.appendingPathComponent("\(coverArtId).jpg")
        guard !FileManager.default.fileExists(atPath: sharedURL.path) else { return }

        var sourceImage: PlatformImage?

        // Prefer the already-persisted local cover (no network needed).
        let localURL = coversDirectory.appendingPathComponent(coverArtId)
        if FileManager.default.fileExists(atPath: localURL.path),
           let data = try? Data(contentsOf: localURL),
           let img = PlatformImage(data: data) {
            sourceImage = img
        } else {
            // Fallback: ask ArtworkImageCache (fetches from server if absent locally).
            sourceImage = await artworkCache.load(coverArtId: coverArtId)
        }

        guard let image = sourceImage else {
            Logger.widget.debug("bridgeCoverArt: no image available for \(coverArtId, privacy: .public)")
            return
        }

        guard let jpgData = image.resized(maxDimension: 600).jpgData(quality: 0.8) else { return }
        try jpgData.write(to: sharedURL, options: .atomic)
        Logger.widget.debug("bridgeCoverArt: bridged \(coverArtId, privacy: .public) (\(jpgData.count) bytes)")
    }

    // MARK: - Throttled timeline reload

    /// Calls WidgetCenter.shared.reloadAllTimelines() at most once per second.
    func reloadTimelinesIfNeeded() {
        let now = Date()
        if let last = lastReloadDate, now.timeIntervalSince(last) < 1.0 { return }
        lastReloadDate = now
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        Logger.widget.debug("reloadAllTimelines triggered")
    }
}
