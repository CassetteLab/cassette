// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftUI
import SwiftData

/// DI root. Creates and wires all services in dependency order.
/// Passed into the SwiftUI environment via \.appContainer.
/// All stored service references are protocol existentials — fully mockable in tests.
@MainActor
final class AppContainer {
    // Observable state objects — created here so they exist on the MainActor
    // before actors are initialized (actors receive them via init injection).
    let playerState = PlayerState()
    let serverState = ServerState()
    let cacheSettings = CacheSettings()

    let modelContainer: ModelContainer
    let keychainService: any KeychainServiceProtocol
    let serverService: any ServerServiceProtocol
    let libraryService: any LibraryServiceProtocol
    let cacheService: any CacheServiceProtocol
    let downloadService: any DownloadServiceProtocol
    let mediaResolver: any MediaResolverProtocol
    let playerService: any PlayerServiceProtocol
    let nowPlayingService: any NowPlayingServiceProtocol
    let favoritesService: any FavoritesServiceProtocol
    let pinService: any PinServiceProtocol
    let playlistService: any PlaylistServiceProtocol
    let radioService: any RadioServiceProtocol
    let toastService = ToastService()
    let networkMonitor = NetworkMonitor()
    let sessionService: PlaybackSessionService
    let dominantColorExtractor = DominantColorExtractor()
    let artworkImageCache: ArtworkImageCache
    let statsService: StatsService
    let wrappedPlaylistService: WrappedPlaylistService

    init(inMemory: Bool = false) throws {
        modelContainer = try ModelContainer.cassette(inMemory: inMemory)
        sessionService = PlaybackSessionService(modelContainer: modelContainer)

        let keychain = KeychainService()
        keychainService = keychain

        let cache = CacheService(modelContainer: modelContainer, maxTracks: cacheSettings.maxTracks)
        cacheService = cache

        let stats = StatsService(modelContainer: modelContainer)
        statsService = stats

        let server = ServerService(state: serverState, keychain: keychain, modelContainer: modelContainer, cacheService: cache, statsService: stats)
        serverService = server
        wrappedPlaylistService = WrappedPlaylistService(serverService: server, statsService: stats)
        radioService = RadioService(serverService: server)

        let library = LibraryService(serverService: server, modelContainer: modelContainer)
        libraryService = library

        let download = DownloadService(serverService: server, modelContainer: modelContainer, toastService: toastService)
        downloadService = download
        artworkImageCache = ArtworkImageCache(downloadService: download, libraryService: library)

        let resolver = MediaResolver(
            downloadService: download,
            cacheService: cache,
            serverService: server,
            serverState: serverState
        )
        mediaResolver = resolver

        let player = PlayerService(state: playerState, mediaResolver: resolver, serverService: server, sessionService: sessionService, artworkImageCache: artworkImageCache, libraryService: library, cacheService: cache, downloadService: download, cacheSettings: cacheSettings, toastService: toastService, statsService: stats)
        playerService = player

        let nowPlaying = NowPlayingService(playerService: player, artworkImageCache: artworkImageCache)
        nowPlayingService = nowPlaying

        favoritesService = FavoritesService(libraryService: library, serverState: serverState, modelContainer: modelContainer)
        pinService = PinService(modelContainer: modelContainer)
        let playlist = PlaylistService(serverService: server, modelContainer: modelContainer, downloadService: download)
        playlistService = playlist

        // Break the circular dependency: PlayerService holds a weak-captured ref to NowPlayingService
        // so it can push explicit snapshots (decision B). Task is fine — both actors are
        // created synchronously above, and setNowPlayingService has no meaningful ordering requirement.
        Task { await player.setNowPlayingService(nowPlaying) }
        Task { [playlist] in await playlist.retryMissingPlaylistDownloads() }
    }
}

// MARK: - ModelContainer factory

extension ModelContainer {
    /// Creates the Cassette ModelContainer.
    /// - Parameter inMemory: Pass `true` in tests — Swift Testing parallelises tests,
    ///   so each test must create its own in-memory container (never shared).
    static func cassette(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            ServerConfig.self,
            CachedTrack.self,
            DownloadedTrack.self,
            DownloadedAlbum.self,
            DownloadedPlaylist.self,
            QueueSnapshot.self,
            FavoriteRecord.self,
            PinnedItem.self,
            PlaybackSession.self,
            PlaybackEvent.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: config)
    }
}

// MARK: - SwiftUI environment key

private struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    var appContainer: AppContainer? {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}
