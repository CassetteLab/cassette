// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog
import SwiftData

// MARK: - Shared launch

extension AppContainer {
    private static let launcher = AppLauncher(makeContainer: { try AppContainer() }, steps: .live)

    /// The process-wide container, launched on first call and shared by every later one.
    ///
    /// Only scene entry points call this — `CassetteApp`, and the CarPlay scene delegate from v2.0.
    /// Everything else keeps receiving its dependencies through `init` or the environment.
    static func launched() async -> AppContainer? {
        await launcher.container()
    }

    /// Returns once the saved session is restored, launching first if needed.
    static func sessionRestored() async {
        await launcher.sessionRestored()
    }
}

// MARK: - Live steps

extension AppLaunchSteps {
    /// The launch that used to run in the window's `.task`, in the same order.
    static let live = AppLaunchSteps(
        prepare: { container in
            Logger.boot.notice("🟡 setup() start")
            await container.setup()
            // Start reachability before the UI is interactive so serverState.isOnline
            // is corrected from its optimistic default before any view loads data.
            container.networkMonitor.start(serverState: container.serverState)
            Logger.boot.notice("🟡 setup() done — nowPlayingService.start()")
            await container.nowPlayingService.start()
            await AppContainer.invalidateCoverArtCacheIfNeeded(artworkCache: container.artworkImageCache)
            Task { await AppContainer.migrateAudioExtensionsIfNeeded(modelContainer: container.modelContainer, audioStreamCache: container.audioStreamCache) }
            Task { await AppContainer.migrateM4AFaststartIfNeeded(modelContainer: container.modelContainer) }
            Logger.boot.notice("🟡 container ready (views will render)")
        },
        restore: { container in
            Logger.boot.notice("🟡 loadPersistedState() start")
            // loadPersistedState must complete before restoreSession so the active
            // server is known when prepareCurrentTrackForRestoration resolves the URL.
            await container.serverService.loadPersistedState()
            Logger.boot.notice("🟡 loadPersistedState() done — activeServer = \(String(describing: container.serverState.activeServer?.baseURL), privacy: .public)")
            await container.playerService.restoreSession()
        },
        background: { container in
            // Cross-device continuation is a bonus, never a gate: the local session is already
            // restored above, so a slow or unreachable server costs the user nothing here.
            Task { _ = await container.playerService.restoreFromOtherDevice() }
            Task { await runCoverArtGarbageCollection(container: container) }
            // After the collector, so it never races the pass that decides what is orphaned.
            Task { await runOfflineCoverHeal(container: container) }
            // Cold start fallback: primary trigger for Wrapped updates (BGTask is best-effort).
            // Fire-and-forget — must never block app launch.
            Task { await runWrappedUpdate(container: container) }
            Task { await runMoodUpdate(container: container) }
            Task { await container.widgetSyncService.fullSync() }
            #if os(iOS)
            CassetteApp.attachBackgroundTasks(to: container)
            #endif
        },
        networkRestored: { container in
            guard container.serverState.isOnline else { return }
            await container.playerService.handleNetworkRestored()
            await container.listenBrainzService.flushOfflineQueue()
        }
    )
}

// MARK: - Housekeeping (moved from CassetteApp, unchanged)

@MainActor
private func runCoverArtGarbageCollection(container: AppContainer) async {
    let context = container.modelContainer.mainContext
    var referencedIds: Set<String> = []

    let albums = (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? []
    for album in albums {
        if let id = album.coverArtId { referencedIds.insert(id) }
    }

    let tracks = (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
    for track in tracks {
        if let id = track.coverArtId { referencedIds.insert(id) }
    }

    let playlists = (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
    for playlist in playlists {
        if let id = playlist.coverArtId { referencedIds.insert(id) }
    }

    let pinned = (try? context.fetch(FetchDescriptor<PinnedItem>())) ?? []
    for item in pinned {
        if let id = item.coverArtId { referencedIds.insert(id) }
    }

    await container.downloadService.garbageCollectOrphanedCovers(referencedIds: referencedIds)
}

/// Restores offline cover art that is referenced by a download but missing from disk.
///
/// One detached pass per launch, never awaited by launch. A shipped sweep deleted these
/// files wholesale for a time and only a download writes them, so without this a library
/// damaged then stays damaged.
@MainActor
private func runOfflineCoverHeal(container: AppContainer) async {
    let state = container.serverState

    // isOnline and isExpensive both start optimistic, so reading them now would be reading
    // a guess: offline, the pass would fire every request and fail them all; on cellular
    // with the setting off it would ignore the user's choice. Wait for the first real path
    // instead, and give up rather than act on the defaults if it never arrives.
    let deadline = Date().addingTimeInterval(10)
    while !state.hasResolvedNetworkPath {
        guard Date() < deadline else {
            Logger.artworkCache.debug("[HEAL] Skipped — no network path resolved within 10s.")
            return
        }
        try? await Task.sleep(for: .milliseconds(100))
    }

    guard state.isOnline else { return }
    // Same rule the player's prefetch follows; no separate setting for this.
    guard PlayerService.shouldProceedWithPrefetch(
        isExpensive: state.isExpensive,
        allowCellular: container.cacheSettings.cacheOverCellular
    ) else {
        Logger.artworkCache.debug("[HEAL] Skipped — metered connection and cellular caching is off.")
        return
    }

    // Albums, tracks and playlists only. PinnedItem cover ids are in the collector's
    // referenced set to protect a file a download may have written, but nothing writes one
    // for a pin on its own — healing them would fetch files the app never creates.
    let context = container.modelContainer.mainContext
    var referencedIds: Set<String> = []
    for album in (try? context.fetch(FetchDescriptor<DownloadedAlbum>())) ?? [] {
        if let id = album.coverArtId { referencedIds.insert(id) }
    }
    for track in (try? context.fetch(FetchDescriptor<DownloadedTrack>())) ?? [] {
        if let id = track.coverArtId { referencedIds.insert(id) }
    }
    for playlist in (try? context.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? [] {
        if let id = playlist.coverArtId { referencedIds.insert(id) }
    }
    guard !referencedIds.isEmpty else { return }

    await container.downloadService.healMissingCovers(referencedIds: referencedIds)
}

@MainActor
private func runWrappedUpdate(container: AppContainer) async {
    guard let serverId = container.serverState.activeServer?.id.uuidString else { return }
    await container.wrappedPlaylistService.handleYearTransitionIfNeeded(serverId: serverId, calendar: .current)
    let result = await container.wrappedPlaylistService.runYearlyPlaylistSyncIfNeeded(serverId: serverId, calendar: .current)
    Logger.wrapped.info("Cold start result: \(String(describing: result), privacy: .public)")
}

/// Cold-start catch-up for the weekly mood refresh. This, not the BGTask, is what users
/// actually experience: iOS grants background time at its own discretion, so the refresh lands
/// on the first launch on or after Wednesday. A no-op on every other launch.
@MainActor
private func runMoodUpdate(container: AppContainer) async {
    guard let serverId = container.serverState.activeServer?.id.uuidString else { return }
    // Wrapped in a background assertion because this is the one path that can start with
    // nothing playing: without it, backgrounding the app a second after launch freezes the sync
    // mid-flight. Progress is per-mood, so an interrupted run still resumes where it stopped.
    let result = await BackgroundActivity.run("mood-playlists") {
        await container.moodPlaylistService.runWeeklySyncIfNeeded(serverId: serverId, calendar: .current)
    }
    Logger.moodPlaylists.info("Cold start result: \(String(describing: result), privacy: .public)")
}
