// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
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

    // MARK: - Recently played

    func onTrackStarted(_ song: DisplayableSong) async {
        let coverArtId = song.coverArtId ?? song.id
        let info = SharedTrackInfo(
            id: song.id,
            title: song.title,
            artist: song.artist ?? "",
            albumID: song.albumId,
            coverArtFilename: "\(coverArtId).jpg"
        )

        var items: [SharedTrackInfo] = []
        if let data = SharedStorage.defaults.data(forKey: SharedStorageKey.recentlyPlayedItems.rawValue),
           let decoded = try? JSONDecoder().decode([SharedTrackInfo].self, from: data) {
            items = decoded
        }
        items.insert(info, at: 0)
        var seen = Set<String>()
        items = items.filter { seen.insert($0.id).inserted }
        if items.count > 10 { items = Array(items.prefix(10)) }

        if let encoded = try? JSONEncoder().encode(items) {
            SharedStorage.defaults.set(encoded, forKey: SharedStorageKey.recentlyPlayedItems.rawValue)
        }

        try? await bridgeCoverArt(coverArtId: coverArtId)
        await syncDominantColors(forCoverArtIds: [coverArtId])
        reloadTimelinesIfNeeded()
        Logger.widget.debug("onTrackStarted: updated recently played (\(items.count) items)")
    }

    // MARK: - Now playing state

    func onPlayStateChanged(isPlaying: Bool, currentSong: DisplayableSong?) async {
        let track: SharedTrackInfo? = currentSong.map { song in
            let coverArtId = song.coverArtId ?? song.id
            return SharedTrackInfo(
                id: song.id,
                title: song.title,
                artist: song.artist ?? "",
                albumID: song.albumId,
                coverArtFilename: "\(coverArtId).jpg"
            )
        }
        let nowPlaying = SharedNowPlayingState(track: track, isPlaying: isPlaying, lastUpdated: Date())
        if let encoded = try? JSONEncoder().encode(nowPlaying) {
            SharedStorage.defaults.set(encoded, forKey: SharedStorageKey.nowPlayingState.rawValue)
        }
        if let song = currentSong {
            let coverArtId = song.coverArtId ?? song.id
            try? await bridgeCoverArt(coverArtId: coverArtId)
            await syncDominantColors(forCoverArtIds: [coverArtId])
        }
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nowPlaying)
        #endif
        Logger.widget.debug("onPlayStateChanged: isPlaying=\(isPlaying), reload NowPlayingWidget (bypass throttle)")
    }

    // MARK: - Pinned items

    func syncPinned() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PinnedItem>(sortBy: [SortDescriptor(\PinnedItem.sortOrder)])
        let dbItems = (try? context.fetch(descriptor)) ?? []

        let shared: [SharedPinnedItem] = dbItems.compactMap { item in
            let kind: SharedPinnedItem.Kind
            switch item.itemType {
            case PinnedItemType.album.rawValue: kind = .album
            case PinnedItemType.playlist.rawValue: kind = .playlist
            default: return nil
            }
            return SharedPinnedItem(
                id: item.itemId,
                kind: kind,
                title: item.displayName,
                subtitle: item.displaySubtitle,
                coverArtFilename: item.coverArtId.map { "\($0).jpg" }
            )
        }

        if let encoded = try? JSONEncoder().encode(shared) {
            SharedStorage.defaults.set(encoded, forKey: SharedStorageKey.pinnedItems.rawValue)
        }

        let coverArtIds = dbItems.compactMap(\.coverArtId)
        for id in coverArtIds {
            try? await bridgeCoverArt(coverArtId: id)
        }
        await syncDominantColors(forCoverArtIds: coverArtIds)
        reloadTimelinesIfNeeded()
        Logger.widget.debug("syncPinned: wrote \(shared.count) pinned items to shared defaults")
    }

    // MARK: - Full sync (cold start)

    func fullSync() async {
        await syncPinned()

        if let data = SharedStorage.defaults.data(forKey: SharedStorageKey.recentlyPlayedItems.rawValue),
           let items = try? JSONDecoder().decode([SharedTrackInfo].self, from: data) {
            let ids = items.compactMap { $0.coverArtFilename.map { String($0.dropLast(4)) } }
            await syncDominantColors(forCoverArtIds: ids)
        }

        Logger.widget.debug("fullSync complete")
    }

    // MARK: - Dominant color sync

    func syncDominantColors(forCoverArtIds ids: [String]) async {
        let allCached = await dominantColorExtractor.cachedColors()
        let filtered = allCached.filter { ids.contains($0.key) }
        guard !filtered.isEmpty else { return }
        SharedStorage.defaults.set(filtered, forKey: SharedStorageKey.dominantColors.rawValue)
        Logger.widget.debug("syncDominantColors: wrote \(filtered.count) colors to shared defaults")
    }

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

        // Trigger extraction while the image is in hand so syncDominantColors
        // finds a cached color even on the very first play of a track.
        await MainActor.run { _ = dominantColorExtractor.dominantColor(for: coverArtId, image: image) }
        Logger.widget.debug("bridgeCoverArt: dominant color extracted for \(coverArtId, privacy: .public)")
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
