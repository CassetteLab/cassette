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
    // Observable state objects — created here so they exist on the MainActor
    // before actors are initialized (actors receive them via init injection).
    let playerState = PlayerState()
    let serverState = ServerState()
    let cacheSettings = CacheSettings()

    let modelContainer: ModelContainer
    let keychainService: any KeychainServiceProtocol
    let serverService: any ServerServiceProtocol
    let libraryService: any LibraryServiceProtocol
    let audioStreamCache: any AudioStreamCacheProtocol
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
    /// Weekly mood playlists. Present regardless of whether AudioMuse is configured — the service
    /// reports .notConfigured and does nothing, so the UI has one place to ask.
    let moodPlaylistService: MoodPlaylistService
    let lyricsService: LyricsService
    let widgetSyncService: WidgetSyncService
    let recommendationService: RecommendationService
    let listenBrainzService: ListenBrainzService
    let externalProvidersStore = ExternalProvidersStore()
    let externalArtworkCache = ExternalArtworkCache()
    let externalArtistImageResolver = ExternalArtistImageResolver()
    let searchHistoryService: SearchHistoryService
    let replayGainService = ReplayGainService()
    let replayGainSettings = ReplayGainSettings()
    let crossfadeSettings = CrossfadeSettings()

    init(inMemory: Bool = false) throws {
        modelContainer = try ModelContainer.cassette(inMemory: inMemory)
        sessionService = PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: inMemory))

        let keychain = KeychainService()
        keychainService = keychain

        let cache = AudioStreamCache(modelContainer: modelContainer, maxTracks: cacheSettings.maxTracks)
        audioStreamCache = cache

        let stats = StatsService(modelContainer: modelContainer)
        statsService = stats

        let server = ServerService(state: serverState, keychain: keychain, modelContainer: modelContainer, audioStreamCache: cache)
        serverService = server
        lyricsService = LyricsService(serverService: server, modelContainer: modelContainer)
        wrappedPlaylistService = WrappedPlaylistService(serverService: server, statsService: stats)
        moodPlaylistService = MoodPlaylistService(serverService: server, serverState: serverState)
        radioService = RadioService(serverService: server)

        let download = DownloadService(serverService: server, modelContainer: modelContainer, toastService: toastService)
        downloadService = download

        let library = LibraryService(serverService: server, modelContainer: modelContainer, downloadService: download, statsService: stats)
        libraryService = library

        artworkImageCache = ArtworkImageCache(downloadService: download, libraryService: library)

        let resolver = MediaResolver(
            downloadService: download,
            audioStreamCache: cache,
            serverService: server,
            serverState: serverState
        )
        mediaResolver = resolver

        let lbClient = ListenBrainzClient(transport: URLSessionListenBrainzTransport())
        let lb = ListenBrainzService(client: lbClient, keychain: keychain)
        listenBrainzService = lb

        let player = PlayerService(state: playerState, mediaResolver: resolver, serverService: server, sessionService: sessionService, artworkImageCache: artworkImageCache, libraryService: library, audioStreamCache: cache, downloadService: download, cacheSettings: cacheSettings, replayGainSettings: replayGainSettings, crossfadeSettings: crossfadeSettings, toastService: toastService, statsService: stats, listenBrainzService: lb)
        _player = player
        playerService = player

        let nowPlaying = NowPlayingService(playerService: player, artworkImageCache: artworkImageCache)
        nowPlayingService = nowPlaying

        favoritesService = FavoritesService(libraryService: library, serverState: serverState, modelContainer: modelContainer)
        let pin = PinService(modelContainer: modelContainer)
        pinService = pin
        let playlist = PlaylistService(serverService: server, modelContainer: modelContainer, downloadService: download)
        playlistService = playlist

        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory unavailable — cannot initialise AppContainer")
        }
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

        let subsonicProvider = SubsonicRecommendationProvider(libraryService: library)
        let lbProvider = ListenBrainzRecommendationProvider(client: lbClient, service: lb, libraryService: library)
        recommendationService = RecommendationService(providers: [lbProvider, subsonicProvider])

        searchHistoryService = SearchHistoryService(container: modelContainer)

        Task { await listenBrainzService.loadPersistedState() }
        Task { await externalArtworkCache.runGarbageCollection() }
    }

    /// Awaited by CassetteApp's `.task` before the UI appears, ensuring
    /// PlayerService→NowPlayingService and PlayerService→WidgetSyncService
    /// wiring is complete before any user interaction is possible.
    func setup() async {
        await _player.setNowPlayingService(nowPlayingService)
        await nowPlayingService.setFavoritesService(favoritesService)
        await _player.setWidgetSyncService(widgetSyncService)
        await _player.setReplayGainService(replayGainService)
        await _player.crossfadeSettingsDidChange()
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
            PlaybackSession.self, // kept for schema-mismatch migration safety; see session() below
            PlaybackEvent.self,
            CachedLyrics.self,
            SearchHistoryEntry.self,
            PlaylistCoverChoice.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Isolated container for playback session data.
    ///
    /// Separating PlaybackSession from the main container means
    /// PlaybackSessionService.savePosition() (every 5 s during playback) no longer
    /// posts change notifications to the main store coordinator. The main context's
    /// @Query<SearchHistoryEntry> never sees these saves, eliminating the continuous
    /// 5-second render cascade that previously fired during all active playback.
    ///
    /// PlaybackSession.self is retained in cassette() purely to avoid a schema-mismatch
    /// migration error when opening existing stores from app versions where it lived
    /// in the main container. That table remains in the main store file but is never
    /// written to after this change.
    /// - Parameter inMemory: Pass `true` in tests.
    static func session(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([PlaybackSession.self])
        let config = ModelConfiguration("cassette-session", schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: config)
    }
}

// MARK: - Cover art cache invalidation

extension AppContainer {
    private static let coverArtCacheVersionKey = "cassette.coverArtCacheVersion"
    private static let currentCoverArtCacheVersion = 5

    /// Purges cover art files from disk on the first launch after a cache format change,
    /// so stale files don't shadow the new decode pipeline. Version history:
    ///   v5 — ArtworkImageCache now decodes at 240 px (thumb) / 1200 px (full) via
    ///         CGImageSourceCreateThumbnailAtIndex; legacy full-res files cause ~800 ms
    ///         decodes on cold open even after the code fix — wipe forces a clean re-download.
    ///   v4 and earlier — previous resolution bumps.
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

// MARK: - Legacy cover art sweep

extension AppContainer {
    private static let artworkLegacySweepKey = "cassette.artworkLegacySweep_v2"

    /// One-shot background sweep that deletes untagged cover art files written by
    /// pre-tier builds (plain `{id}` filenames with no `@thumb` / `@hero` suffix).
    ///
    /// These full-res JPEGs can be 2–4 MB each; decoding them at the 240px thumb
    /// size took ~1100ms per file on a background thread, starving the audio decode
    /// thread and causing audible crackling during queue load. ArtworkImageCache no
    /// longer reads them (since the legacy fallback was removed), but they still
    /// waste disk space and could confuse future disk-hit logic. Deleting them here
    /// forces a clean re-download at the correct tier size.
    static func sweepLegacyCoverArtFiles() {
        guard !UserDefaults.standard.bool(forKey: artworkLegacySweepKey) else { return }

        Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let coverArtsDir = docs.appendingPathComponent("app.cassette/coverarts", isDirectory: true)

            guard let items = try? fm.contentsOfDirectory(at: coverArtsDir, includingPropertiesForKeys: nil) else { return }

            var deletedCount = 0
            for fileURL in items {
                let name = fileURL.lastPathComponent
                // Keep files that have a tier suffix; delete untagged legacy files.
                guard !name.contains("@thumb") && !name.contains("@hero") else { continue }
                do {
                    try fm.removeItem(at: fileURL)
                    deletedCount += 1
                } catch {
                    Logger.artworkCache.warning("[SWEEP] Failed to delete legacy cover '\(name, privacy: .public)': \(error, privacy: .public)")
                }
            }

            await MainActor.run {
                UserDefaults.standard.set(true, forKey: artworkLegacySweepKey)
            }
            Logger.artworkCache.info("[SWEEP] Legacy cover art sweep complete: \(deletedCount) files deleted")
        }
    }
}

// MARK: - Audio extension migration

extension AppContainer {
    private static let audioExtMigrationKey = "cassette.audioExtMigration_v1"

    /// One-shot migration that fixes downloaded tracks saved with a `.mpeg` extension.
    ///
    /// Root cause: the original DownloadService derived the file extension from the HTTP
    /// Content-Type header. `audio/mpeg` → `.mpeg`, which AVPlayer maps to a video UTI
    /// (public.mpeg) instead of public.mp3, causing silent playback failure for MP3 files.
    ///
    /// This migration:
    /// 1. Purges the ephemeral AudioStreamCache (all entries may carry .mpeg).
    /// 2. Renames permanent downloaded files from .mpeg to the correct extension using
    ///    the server-declared `suffix` stored in DownloadedTrack, falling back to a
    ///    MIME-type map when suffix is absent.
    /// 3. Updates the SwiftData filePath records for each successfully renamed file.
    static func migrateAudioExtensionsIfNeeded(
        modelContainer: ModelContainer,
        audioStreamCache: any AudioStreamCacheProtocol
    ) async {
        guard !UserDefaults.standard.bool(forKey: audioExtMigrationKey) else { return }

        await audioStreamCache.clearAll()
        Logger.migration.info("[ExtMigration] Ephemeral audio cache cleared")

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = docs.appendingPathComponent("app.cassette/downloads", isDirectory: true)

        let ctx = ModelContext(modelContainer)
        let tracks = (try? ctx.fetch(FetchDescriptor<DownloadedTrack>())) ?? []

        var renamedCount = 0
        var skippedCount = 0

        for track in tracks {
            guard track.filePath.hasSuffix(".mpeg") else { continue }
            let desiredExt: String
            if let s = track.suffix, !s.isEmpty {
                desiredExt = s
            } else {
                desiredExt = Self.audioExtFromMime(track.mimeType)
            }
            guard desiredExt != "mpeg" else { continue }

            let oldPath = track.filePath
            let newPath = String(oldPath.dropLast(".mpeg".count)) + ".\(desiredExt)"
            let oldURL = downloadsDir.appendingPathComponent(oldPath)
            let newURL = downloadsDir.appendingPathComponent(newPath)

            guard FileManager.default.fileExists(atPath: oldURL.path) else {
                Logger.migration.warning("[ExtMigration] File missing, skipping: '\(oldPath, privacy: .public)'")
                skippedCount += 1
                continue
            }
            do {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try FileManager.default.removeItem(at: newURL)
                }
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                track.filePath = newPath
                renamedCount += 1
                Logger.migration.info("[ExtMigration] '\(oldPath, privacy: .public)' → '\(newPath, privacy: .public)'")
            } catch {
                Logger.migration.error("[ExtMigration] Rename failed '\(oldPath, privacy: .public)': \(error, privacy: .public)")
                skippedCount += 1
            }
        }

        try? ctx.save()
        UserDefaults.standard.set(true, forKey: audioExtMigrationKey)
        Logger.migration.info("[ExtMigration] Complete: \(renamedCount) renamed, \(skippedCount) skipped")
    }

    // v3: v2 was burned on installs that ran it against an EMPTY download set (fresh install) —
    // it set the done-flag on a clean-but-empty pass, so the scan→remux path was never exercised.
    // The version bump re-runs the migration; both keys bump together so the attempt counter resets.
    private static let m4aFaststartMigrationKey = "cassette.m4aFaststartMigration_v3"
    private static let m4aFaststartAttemptsKey = "cassette.m4aFaststartMigration_v3_attempts"
    private static let m4aFaststartMaxAttempts = 3

    /// Migration that faststart-remuxes already-downloaded m4a tracks so they play offline through
    /// AudioStreaming (which cannot open non-faststart M4A). Fire-and-forget at boot.
    ///
    /// Retry-safe (unlike v1): the done-flag is set ONLY on a clean pass — save succeeded AND no
    /// track failed to remux. Failed tracks (e.g. a transient export failure at boot) are retried
    /// on the next launch, up to `m4aFaststartMaxAttempts` passes, after which it gives up so a
    /// genuinely irrecoverable file can't trigger an eternal boot-time retry.
    ///
    /// Detection is CONTENT-based (`ftyp` sniff), not extension-based, so a mis-served m4a that an
    /// earlier migration renamed `.mp3` is still caught. A remux REWRITES the bytes, so
    /// `DownloadedTrack.fileSize` is refreshed from the remuxed file (with the same `?? 0` fallback
    /// as the download path, so `downloadedURL`'s `fileSize == 0` escape covers a size-read miss
    /// instead of persisting a stale, mismatched size). Scope: DownloadedTrack only (CachedTrack = Phase 2).
    static func migrateM4AFaststartIfNeeded(modelContainer: ModelContainer) async {
        guard !UserDefaults.standard.bool(forKey: m4aFaststartMigrationKey) else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = docs.appendingPathComponent("app.cassette/downloads", isDirectory: true)

        let ctx = ModelContext(modelContainer)
        let tracks = (try? ctx.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
        let remuxer = AudioFaststartRemuxer()

        var remuxedCount = 0
        var failedCount = 0
        var m4aCount = 0
        for track in tracks {
            let fileURL = downloadsDir.appendingPathComponent(track.filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            // Content sniff, not extension — catches a container with a wrong/renamed extension.
            guard AudioFaststartRemuxer.isM4AContainer(atPath: fileURL.path) else { continue }
            m4aCount += 1
            switch await remuxer.remuxToFaststartIfNeeded(at: fileURL) {
            case .remuxed:
                // Bytes changed — refresh fileSize from the remuxed file (?? 0 mirrors the
                // download path, where downloadedURL's `== 0` escape tolerates a read miss).
                let newSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                track.fileSize = newSize
                remuxedCount += 1
                Logger.migration.info("[M4AFaststart] faststart-remuxed '\(track.songId, privacy: .public)'")
            case .failed:
                failedCount += 1
                Logger.migration.warning("[M4AFaststart] export failed '\(track.songId, privacy: .public)' — will retry next boot")
            case .skipped:
                break   // already faststart or not an MP4 container — nothing to do
            }
        }

        // Persist the fileSize updates; only mark done on a clean pass so failures are retried.
        var saveOK = true
        do {
            try ctx.save()
        } catch {
            saveOK = false
            Logger.migration.error("[M4AFaststart] save failed: \(error, privacy: .public) — not marking done, will retry")
        }

        let attempts = UserDefaults.standard.integer(forKey: m4aFaststartAttemptsKey) + 1
        UserDefaults.standard.set(attempts, forKey: m4aFaststartAttemptsKey)
        let giveUp = attempts >= m4aFaststartMaxAttempts
        if saveOK && (failedCount == 0 || giveUp) {
            UserDefaults.standard.set(true, forKey: m4aFaststartMigrationKey)
            if failedCount > 0 {
                Logger.migration.warning("[M4AFaststart] giving up after \(attempts) attempts with \(failedCount) still failing")
            }
        }
        Logger.migration.info("[M4AFaststart] Complete: \(remuxedCount) remuxed, \(failedCount) failed of \(m4aCount) m4a (\(tracks.count) total), attempt \(attempts)")
    }

    private static func audioExtFromMime(_ mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "audio/mpeg", "audio/mp3":        return "mp3"
        case "audio/flac", "audio/x-flac":     return "flac"
        case "audio/mp4", "audio/m4a",
             "audio/aac", "audio/x-aac":       return "m4a"
        case "audio/ogg":                       return "ogg"
        case "audio/opus":                      return "opus"
        case "audio/wav", "audio/x-wav":       return "wav"
        case "audio/aiff", "audio/x-aiff":     return "aiff"
        default:                                return "mpeg"
        }
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
