// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import OSLog
import SwiftUI
import SwiftData

/// DI root. Creates and wires all services in dependency order.
/// Passed into the SwiftUI environment via \.appContainer.
/// All stored service references are protocol existentials — fully mockable in tests.
@MainActor
final class AppContainer {
    nonisolated(unsafe) static var shared: AppContainer?
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
    private let _player: PlayerService
    let wrappedPlaylistService: WrappedPlaylistService
    let lyricsService: LyricsService
    let widgetSyncService: WidgetSyncService
    let recommendationService: RecommendationService
    let listenBrainzService: ListenBrainzService
    let externalProvidersStore = ExternalProvidersStore()
    let externalArtworkCache = ExternalArtworkCache()
    let externalArtistImageResolver = ExternalArtistImageResolver()

    init(inMemory: Bool = false) throws {
        modelContainer = try ModelContainer.cassette(inMemory: inMemory)
        sessionService = PlaybackSessionService(modelContainer: modelContainer)

        let keychain = KeychainService()
        keychainService = keychain

        let cache = CacheService(modelContainer: modelContainer, maxTracks: cacheSettings.maxTracks)
        cacheService = cache

        let stats = StatsService(modelContainer: modelContainer)
        statsService = stats

        let server = ServerService(state: serverState, keychain: keychain, modelContainer: modelContainer, cacheService: cache)
        serverService = server
        lyricsService = LyricsService(serverService: server, modelContainer: modelContainer)
        wrappedPlaylistService = WrappedPlaylistService(serverService: server, statsService: stats)
        radioService = RadioService(serverService: server)

        let download = DownloadService(serverService: server, modelContainer: modelContainer, toastService: toastService)
        downloadService = download

        let library = LibraryService(serverService: server, modelContainer: modelContainer, downloadService: download)
        libraryService = library

        artworkImageCache = ArtworkImageCache(downloadService: download, libraryService: library)

        let resolver = MediaResolver(
            downloadService: download,
            cacheService: cache,
            serverService: server,
            serverState: serverState
        )
        mediaResolver = resolver

        let player = PlayerService(state: playerState, mediaResolver: resolver, serverService: server, sessionService: sessionService, artworkImageCache: artworkImageCache, libraryService: library, cacheService: cache, downloadService: download, cacheSettings: cacheSettings, toastService: toastService, statsService: stats)
        _player = player
        playerService = player

        let nowPlaying = NowPlayingService(playerService: player, artworkImageCache: artworkImageCache)
        nowPlayingService = nowPlaying

        favoritesService = FavoritesService(libraryService: library, serverState: serverState, modelContainer: modelContainer)
        let pin = PinService(modelContainer: modelContainer)
        pinService = pin
        let playlist = PlaylistService(serverService: server, modelContainer: modelContainer, downloadService: download)
        playlistService = playlist

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let coversDir = docs.appendingPathComponent("app.cassette/coverarts", isDirectory: true)
        let widgetSync = WidgetSyncService(
            dominantColorExtractor: dominantColorExtractor,
            modelContainer: modelContainer,
            artworkCache: artworkImageCache,
            coversDirectory: coversDir,
            serverState: serverState
        )
        widgetSyncService = widgetSync
        pin.setWidgetSyncService(widgetSync)

        NowPlayingBridge.performTogglePlayPause = { [weak player] in await player?.togglePlayPause() }
        Task { [playlist] in await playlist.retryMissingPlaylistDownloads() }

        let lbClient = ListenBrainzClient(transport: URLSessionListenBrainzTransport())
        listenBrainzService = ListenBrainzService(client: lbClient, keychain: keychain)

        let subsonicProvider = SubsonicRecommendationProvider(libraryService: library)
        let lbProvider = ListenBrainzRecommendationProvider(client: lbClient, service: listenBrainzService, libraryService: library)
        recommendationService = RecommendationService(providers: [lbProvider, subsonicProvider])

        Task { await listenBrainzService.loadPersistedState() }
        Task { await externalArtworkCache.runGarbageCollection() }
    }

    /// Awaited by CassetteApp's `.task` before the UI appears, ensuring
    /// PlayerService→NowPlayingService and PlayerService→WidgetSyncService
    /// wiring is complete before any user interaction is possible.
    func setup() async {
        await _player.setNowPlayingService(nowPlayingService)
        await _player.setWidgetSyncService(widgetSyncService)
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
            PlaybackEvent.self,
            CachedLyrics.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: config)
    }
}

// MARK: - Cover art cache invalidation

extension AppContainer {
    private static let coverArtCacheVersionKey = "cassette.coverArtCacheVersion"
    private static let currentCoverArtCacheVersion = 4

    /// Purges low-resolution cover art files from disk on the first launch after a
    /// resolution bump, so stale cached files don't shadow higher-quality server fetches.
    static func invalidateCoverArtCacheIfNeeded(artworkCache: ArtworkImageCache) {
        let stored = UserDefaults.standard.integer(forKey: coverArtCacheVersionKey)
        guard stored < currentCoverArtCacheVersion else { return }

        artworkCache.clearCache()
        let coverArtsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.cassette/coverarts")
        try? FileManager.default.removeItem(at: coverArtsDir)
        try? FileManager.default.createDirectory(at: coverArtsDir, withIntermediateDirectories: true)
        URLCache.shared.removeAllCachedResponses()

        UserDefaults.standard.set(currentCoverArtCacheVersion, forKey: coverArtCacheVersionKey)
        Logger.player.info("ArtworkImageCache: invalidated cover art disk cache (version \(stored) → \(currentCoverArtCacheVersion))")
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
