// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import AudioStreaming
import SwiftSonic
import OSLog

#if os(iOS)
import AVFAudio
#endif

nonisolated enum CrossfadePhase: Sendable {
    case fadeOut
    case fadeIn
}

actor PlayerService: PlayerServiceProtocol {
    nonisolated let state: PlayerState

    private let mediaResolver: any MediaResolverProtocol
    private let serverService: any ServerServiceProtocol
    private let sessionService: PlaybackSessionService
    private let artworkImageCache: ArtworkImageCache
    private let libraryService: any LibraryServiceProtocol
    private let audioStreamCache: any AudioStreamCacheProtocol
    private let downloadService: any DownloadServiceProtocol
    private let cacheSettings: CacheSettings
    private let replayGainSettings: ReplayGainSettings
    private let crossfadeSettings: CrossfadeSettings
    private var crossfadeConfig = CrossfadeConfig(duration: 0, disableForGapless: true)
    private var nowPlayingService: (any NowPlayingServiceProtocol)?
    private var widgetSyncService: WidgetSyncService?
    private var replayGainService: ReplayGainService?
    private let toastService: ToastService
    private let statsService: StatsService
    private let listenBrainzService: ListenBrainzService

    // AudioStreaming — single instance for the session lifetime.
    // nonisolated(unsafe): constant references; AudioPlayer has its own internal queue.
    private nonisolated(unsafe) let audioPlayer: AudioPlayer
    private let audioDelegate: AudioStreamingDelegate
    private var progressTask: Task<Void, Never>?
    /// Pending seek + optional pause applied once the player first reaches `.playing`.
    /// Used for session restoration and end-of-queue rewind.
    private var pendingRestoreInfo: (seekTime: Double, pause: Bool)?
    /// Source of the currently playing track; kept for repeat-one replay.
    private var currentSource: MediaSource?
    private var liveStreamStallTask: Task<Void, Never>?

    private var audioSessionConfigured = false
    #if os(iOS)
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    /// Stored so pause()/stop() can cancel it before calling setActive(false),
    /// preventing a stale retry from reactivating the session after the user stops.
    private var sessionActivationRetryTask: Task<Void, Never>?
    /// True when the current interruption began because the output route was disconnected
    /// (AirPods in case). Per Apple guidance, never auto-resume after such an interruption
    /// — resuming would route playback to the built-in speaker.
    private var interruptionWasRouteDisconnect = false
    #endif

    private var isHandlingEndOfTrack = false
    /// True when playback stopped cleanly at the END of the queue (repeat off). `resume()` reads this to restart
    /// from track 0 instead of replaying the last track (which would hit EOF and re-stop — the mini-loop).
    /// Cleared by any real playback start (`play`).
    private var stoppedAtEndOfQueue = false
    /// True during the URL-resolution phase of session restore (prepareCurrentTrackForRestoration).
    /// Blocks handleEndOfTrack() and handleNetworkRestored() during that window.
    private var isRestoringSession = false
    /// Stored handle for the 150 ms deferred-pause task during session restore.
    /// Cancelled by resume() if the user taps play before the pause fires.
    private var restorePauseTask: Task<Void, Never>?
    /// True while the player is muted for the restore seek window (150 ms).
    /// Ensures volume is restored whether the pause fires or the user taps play first.
    private var isMutedForRestore = false
    /// Last saved volume from UserDefaults, defaulting to 0.7 when the key was never written.
    /// setVolume() never persists 0, so a missing key and an intentional-0 are indistinguishable
    /// here — using 0.7 as the initial default is correct.
    nonisolated var restoredVolume: Float {
        guard UserDefaults.standard.object(forKey: "cassette.lastVolume") != nil else { return 0.7 }
        return Float(UserDefaults.standard.double(forKey: "cassette.lastVolume"))
    }
    private var positionSaveTask: Task<Void, Never>?
    /// Task reserved for the playing-now notification. Cancelled on track change.
    private var playingNowTask: Task<Void, Never>?
    private var detector = ScrobbleThresholdDetector()
    /// Task scheduled to download and cache the current track at +30s of playback.
    /// Cancelled when track changes via cancelPendingCacheDownload().
    private var cacheDownloadTask: Task<Void, Never>?
    private let cacheSession: URLSession
    /// Task that prefetches the next queued track into cache ahead of the crossfade window.
    /// Cancelled on every track transition via cancelPendingPrefetch().
    private var prefetchTask: Task<Void, Never>?
    private var prefetchScheduled = false
    private let prefetchSession: URLSession
    /// Fade-out task running during the crossfade window at the end of the current track.
    private var fadeOutTask: Task<Void, Never>?
    /// Fade-in task running at the start of the next track after a crossfade.
    private var fadeInTask: Task<Void, Never>?
    /// True while a crossfade fade-out is in progress; guards checkFadeOutThreshold against re-entry.
    private var isFadingOut = false
    // Saved before a shuffle activation; nil when shuffle is off.
    private var originalQueueOrder: [DisplayableSong]?
    /// Single-slot guard preventing concurrent auto-extend fetches.
    private var autoExtendFetchTask: Task<Void, Never>?
    /// True while an Instant Mix is still assembling its tracks behind the already-playing seed.
    /// While set, auto-extend is suppressed: the seed plays as a one-track queue, and without this an
    /// already-enabled endless mode would see "0 remaining" and immediately backfill 50 generic
    /// library tracks — racing the mix, duplicating the queue, and jumping ahead of the real similar
    /// songs. Cleared the moment the mix lands (or its build fails / is abandoned).
    private var isBuildingInstantMix = false
    private nonisolated static let autoExtendUserDefaultsKey = "cassette.player.autoExtendEnabled"

    /// Wall-clock time when the current track first started (used as event timestamp). Nil before first track.
    private var trackPlayStartDate: Date?
    /// Seconds of actual (non-paused) playback accumulated for the current track.
    private var accumulatedPlayedSeconds: TimeInterval = 0
    /// Wall-clock start of the current play segment; nil when paused or stopped.
    private var currentPlaySegmentStart: Date?
    /// Set to true by handleEndOfTrack before a natural completion transition; reset after recording.
    private var wasTrackCompletedNaturally: Bool = false

    init(
        state: PlayerState,
        mediaResolver: any MediaResolverProtocol,
        serverService: any ServerServiceProtocol,
        sessionService: PlaybackSessionService,
        artworkImageCache: ArtworkImageCache,
        libraryService: any LibraryServiceProtocol,
        audioStreamCache: any AudioStreamCacheProtocol,
        downloadService: any DownloadServiceProtocol,
        cacheSettings: CacheSettings,
        replayGainSettings: ReplayGainSettings,
        crossfadeSettings: CrossfadeSettings,
        toastService: ToastService,
        statsService: StatsService,
        listenBrainzService: ListenBrainzService
    ) {
        self.state = state
        self.mediaResolver = mediaResolver
        self.serverService = serverService
        self.sessionService = sessionService
        self.artworkImageCache = artworkImageCache
        self.libraryService = libraryService
        self.audioStreamCache = audioStreamCache
        self.downloadService = downloadService
        self.cacheSettings = cacheSettings
        self.replayGainSettings = replayGainSettings
        self.crossfadeSettings = crossfadeSettings
        self.toastService = toastService
        self.statsService = statsService
        self.listenBrainzService = listenBrainzService
        let cacheConfig = URLSessionConfiguration.default
        cacheConfig.timeoutIntervalForRequest = 30
        cacheConfig.timeoutIntervalForResource = 30
        self.cacheSession = URLSession(configuration: cacheConfig)

        let prefetchConfig = URLSessionConfiguration.default
        prefetchConfig.timeoutIntervalForRequest = 30
        prefetchConfig.timeoutIntervalForResource = 300
        prefetchConfig.networkServiceType = .background
        self.prefetchSession = URLSession(configuration: prefetchConfig)

        let playerConfig = AudioPlayerConfiguration(
            flushQueueOnSeek: true,
            bufferSizeInSeconds: 20,
            secondsRequiredToStartPlaying: 1,
            gracePeriodAfterSeekInSeconds: 0.5,
            secondsRequiredToStartPlayingAfterBufferUnderrun: 1,
            enableLogs: false
        )
        let player = AudioPlayer(configuration: playerConfig)
        let delegate = AudioStreamingDelegate()
        self.audioPlayer = player
        self.audioDelegate = delegate
        // Wire delegate after all stored properties are initialised.
        delegate.service = self
        player.delegate = delegate
    }

    /// Call from AppContainer after both PlayerService and NowPlayingService are created.
    func setNowPlayingService(_ service: any NowPlayingServiceProtocol) {
        nowPlayingService = service
    }

    func setWidgetSyncService(_ service: WidgetSyncService) {
        widgetSyncService = service
    }

    func setReplayGainService(_ service: ReplayGainService) async {
        replayGainService = service
        await service.attach(to: audioPlayer)
    }

    // MARK: - Play

    func play(tracks: [DisplayableSong], startIndex: Int) async throws {
        guard tracks.indices.contains(startIndex) else { return }
        stoppedAtEndOfQueue = false

        // Reset shuffle only when starting a genuinely new queue, not on internal skips
        // (skipToNext/skipToPrevious pass state.queue unchanged, so IDs match).
        let currentQueueIds = await MainActor.run { state.queue.map(\.id) }
        if tracks.map(\.id) != currentQueueIds {
            originalQueueOrder = nil
            await MainActor.run {
                state.isShuffled = false
                state.originalQueueEndIndex = nil
                if state.isSmartShuffleActive {
                    state.isSmartShuffleActive = false
                    Logger.player.debug("Ending Smart Shuffle session — starting new explicit queue")
                }
            }
        }

        guard let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) else {
            await MainActor.run { state.playbackState = .error(.serverNotConfigured) }
            throw CassetteError.serverNotConfigured
        }

        await MainActor.run {
            if state.currentRadio != nil {
                Logger.player.debug("Ending live stream session — switching to queue playback")
            }
            state.queue = tracks
            state.currentIndex = startIndex
            state.currentRadio = nil
            state.playbackState = .loading
        }

        let song = tracks[startIndex]
        let source: MediaSource
        do {
            source = try await mediaResolver.resolve(songId: song.id, serverId: serverId)
        } catch let e as CassetteError {
            await MainActor.run { state.playbackState = .error(e) }
            throw e
        } catch {
            await MainActor.run { state.playbackState = .idle }
            throw error
        }

        await startPlayback(song: song, source: source, serverId: serverId)
    }

    private func startPlayback(song: DisplayableSong, source: MediaSource, serverId: UUID) async {
        // Record the previous track before transitioning (state.currentTrack still holds it here).
        await recordCurrentTrackPlayback(trigger: wasTrackCompletedNaturally ? "track_completed" : "user_skipped")
        wasTrackCompletedNaturally = false
        resetTrackAccumulator(isPlaying: true)

        // Cancel any pending +30s scrobble, cache download, and prefetch from the previous track.
        cancelPendingScrobble()
        cancelPendingCacheDownload()
        cancelPendingPrefetch()
        // Capture crossfade intent before cancelling fade tasks.
        // Manual cancel here (without volume restore) — volume is set explicitly below.
        let shouldFadeIn = isFadingOut && crossfadeConfig.duration > 0
        fadeOutTask?.cancel(); fadeOutTask = nil
        fadeInTask?.cancel(); fadeInTask = nil
        isFadingOut = false

        let config = await MainActor.run { replayGainSettings.config }
        await replayGainService?.apply(track: song, config: config)

        let songId = song.id
        Task { [libraryService] in
            await libraryService.scrobble(songId: songId, submission: false)
        }
        playingNowTask = Task { [listenBrainzService, weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            let stillActive = await MainActor.run { self.state.playbackState == .playing && self.state.currentTrack?.id == song.id }
            guard stillActive else { return }
            await listenBrainzService.notifyTrackStarted(song: song)
        }
        // Schedule cache download for stream sources only. Same +30s threshold as scrobble.
        // Phase 3: reads cacheSettings for format and cellular policy.
        if case .stream(let streamURL, let customHeaders) = source {
            // Capture settings at task-creation time — in-flight tasks use values from when they were scheduled.
            let (allowCellular, cacheFormat) = await MainActor.run {
                (cacheSettings.cacheOverCellular, cacheSettings.cacheFormat)
            }

            let cacheStreamURL: URL?
            if cacheFormat == .matchStream {
                cacheStreamURL = streamURL
            } else {
                cacheStreamURL = (try? await serverService.makeSwiftSonicClient())?.streamURL(
                    id: songId,
                    maxBitRate: cacheFormat.subsonicMaxBitRate,
                    format: cacheFormat.subsonicFormat
                )
            }

            if let cacheStreamURL {
                cacheDownloadTask = Task { [audioStreamCache, downloadService, serverService, cacheSession, weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    if await audioStreamCache.cachedURL(forSongId: songId, serverId: serverId) != nil { return }
                    if await downloadService.isDownloaded(songId: songId, serverId: serverId) { return }
                    let isExpensive = await MainActor.run { serverService.state.isExpensive }
                    if isExpensive && !allowCellular {
                        Logger.player.debug("Cache skipped — cellular for '\(songId, privacy: .public)'")
                        return
                    }
                    do {
                        // TODO(crossfade-followup): cacheSession 30s resource timeout caps large-file caching on slow links
                        try await self?.downloadAndCache(
                            songId: songId,
                            serverId: serverId,
                            streamURL: cacheStreamURL,
                            customHeaders: customHeaders,
                            using: cacheSession
                        )
                    } catch {
                        Logger.player.debug("Cache download failed for '\(songId, privacy: .public)': \(error, privacy: .public)")
                    }
                }
            } else {
                Logger.player.debug("Cache: no URL for '\(songId, privacy: .public)' in \(cacheFormat.rawValue) — skipping")
            }
        }

        Logger.player.info("[TRANSITION] advancing to '\(song.title, privacy: .public)' (id=\(song.id, privacy: .public)) — starting AudioStreaming")

        stopProgressTimer()
        liveStreamStallTask?.cancel()
        liveStreamStallTask = nil
        currentSource = source
        pendingRestoreInfo = nil
        // Starting a new track can interrupt a muted parking play (end-of-queue rewind)
        // without going through resume()/stop() — cancel the deferred pause and unmute,
        // otherwise the new track would start silent or get paused 150 ms in.
        restorePauseTask?.cancel()
        restorePauseTask = nil
        if isMutedForRestore {
            audioPlayer.volume = restoredVolume
            isMutedForRestore = false
        }

        #if os(iOS)
        configureAudioSessionIfNeeded()
        #endif

        let fadingInAllowed: Bool
        #if os(iOS)
        fadingInAllowed = shouldFadeIn && !PlayerService.isProblematicRoute(
            portTypes: AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType }
        )
        #else
        fadingInAllowed = shouldFadeIn
        #endif

        if fadingInAllowed {
            audioPlayer.volume = 0
        }
        audioPlayer.play(url: source.url, headers: source.customHeaders)
        if fadingInAllowed {
            performFadeIn(duration: crossfadeConfig.duration)
        }

        let duration = song.duration
        await MainActor.run {
            state.currentTrack = song
            state.duration = duration
            state.position = 0
            state.playbackState = .playing
            state.isPlaybackAvailable = true
        }

        startProgressTimer()

        let artworkURL = await resolveArtworkURL(for: song)
        Logger.player.debug("[TRANSITION] attempting credentials fetch for NowPlaying headers")
        let artworkHeaders: [String: String]
        do {
            artworkHeaders = try await serverService.activeCredentials().customHeaders
        } catch {
            Logger.player.warning("[CREDENTIALS] activeCredentials failed, using empty headers: \(error, privacy: .public)")
            artworkHeaders = [:]
        }
        let snapshot = NowPlayingSnapshot(
            title: song.title,
            artist: song.artist,
            album: song.albumName,
            duration: duration,
            position: 0,
            playbackRate: 1.0,
            artworkURL: artworkURL,
            artworkHeaders: artworkHeaders,
            coverArtId: song.coverArtId,
            isLiveStream: false,
            radioStationName: nil,
            songId: song.id
        )
        await nowPlayingService?.update(with: snapshot)
        await saveSession()
        startPositionSaveTimer()
        preloadNextTrackArtwork()
        await evaluateAutoExtend()
        if let ws = widgetSyncService {
            Task { await ws.onTrackStarted(song) }
        }
        if let ws = widgetSyncService {
            Task { [weak ws] in await ws?.onPlayStateChanged(isPlaying: true, currentSong: song) }
        }
    }

    // MARK: - Live Stream

    func playRadio(_ station: InternetRadioStation) async throws {
        cancelPendingScrobble()
        cancelPendingCacheDownload()
        cancelFadeTasks()
        let source = try await mediaResolver.resolveRadio(station)

        let codecResult = await checkCodecSupport(url: source.url, headers: source.customHeaders)
        if case .unsupported(let contentType) = codecResult {
            Logger.player.warning("[RADIO-CODEC] rejected stream, content-type=\(contentType, privacy: .public)")
            await MainActor.run {
                toastService.show(
                    "This radio uses an unsupported audio format. Cassette can play MP3 and AAC live streams currently.",
                    style: .error,
                    duration: 5.0
                )
            }
            return
        }

        stopProgressTimer()
        liveStreamStallTask?.cancel()
        liveStreamStallTask = nil
        currentSource = source
        pendingRestoreInfo = nil
        // Same recovery as startPlayback(): a radio start can interrupt a muted
        // parking play — cancel the deferred pause and unmute before playing.
        restorePauseTask?.cancel()
        restorePauseTask = nil
        if isMutedForRestore {
            audioPlayer.volume = restoredVolume
            isMutedForRestore = false
        }

        #if os(iOS)
        configureAudioSessionIfNeeded()
        #endif

        await MainActor.run {
            state.currentTrack = nil
            state.currentRadio = station
            state.isSmartShuffleActive = false
            state.originalQueueEndIndex = nil
            state.playbackState = .loading
            state.position = 0
            state.duration = 0
        }

        audioPlayer.play(url: source.url, headers: source.customHeaders)

        await MainActor.run {
            state.playbackState = .playing
            state.isPlaybackAvailable = true
        }

        startProgressTimer()
        startLiveStreamStallMonitor(stationName: station.name)

        let artworkHeaders: [String: String]
        do {
            artworkHeaders = try await serverService.activeCredentials().customHeaders
        } catch {
            Logger.player.warning("[CREDENTIALS] activeCredentials failed, using empty headers: \(error, privacy: .public)")
            artworkHeaders = [:]
        }
        await nowPlayingService?.update(with: NowPlayingSnapshot(
            title: station.name,
            artist: "Live Radio",
            album: nil,
            duration: 0,
            position: 0,
            playbackRate: 1.0,
            artworkURL: nil,
            artworkHeaders: artworkHeaders,
            coverArtId: station.coverArt,
            isLiveStream: true,
            radioStationName: station.name,
            songId: nil
        ))

        startPositionSaveTimer()
        Logger.player.info("Started live stream radio '\(station.name, privacy: .public)'")
    }

    // MARK: - Live Stream Codec Check & Failsafe

    private nonisolated enum LiveStreamCodecResult {
        case supported
        case unsupported(contentType: String)
        case ambiguous
    }

    private func checkCodecSupport(url: URL, headers: [String: String]) async -> LiveStreamCodecResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 2.0)
        request.httpMethod = "HEAD"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            Logger.player.debug("[RADIO-CODEC] HEAD request failed or timed out — letting player try")
            return .ambiguous
        }
        let rawType = (httpResponse.allHeaderFields["Content-Type"] as? String ?? "").lowercased()
        let contentType = rawType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""

        let whitelist: Set<String> = ["audio/mpeg", "audio/mp4", "audio/aac", "audio/x-aac", "audio/aacp"]
        let blacklist: Set<String> = ["audio/flac", "audio/x-flac", "audio/opus", "audio/ogg", "audio/vorbis"]

        if whitelist.contains(contentType) {
            Logger.player.debug("[RADIO-CODEC] content-type=\(contentType, privacy: .public) → supported")
            return .supported
        }
        if blacklist.contains(contentType) {
            return .unsupported(contentType: contentType)
        }
        Logger.player.debug("[RADIO-CODEC] content-type=\(contentType.isEmpty ? "(empty)" : contentType, privacy: .public) → ambiguous, letting player try")
        return .ambiguous
    }

    private func startLiveStreamStallMonitor(stationName: String) {
        liveStreamStallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let (isStillLive, position) = await MainActor.run { (self.state.isLiveStream, self.state.position) }
            guard isStillLive, position < 1.0 else { return }
            await self.handleLiveStreamFailure(stationName: stationName, error: nil)
        }
    }

    private func handleLiveStreamFailure(stationName: String, error: Error?) async {
        let isStillLive = await MainActor.run { state.isLiveStream }
        guard isStillLive else { return }

        Logger.player.error("[RADIO-FAILSAFE] live stream '\(stationName, privacy: .public)' failed: \(error?.localizedDescription ?? "stall timeout", privacy: .public)")

        stopProgressTimer()
        audioPlayer.stop()

        await MainActor.run {
            state.currentRadio = nil
            state.playbackState = .idle
            toastService.show(
                "Stream unavailable. The radio may be down or use an unsupported format.",
                style: .error,
                duration: 5.0
            )
        }
    }

    // MARK: - Smart Shuffle

    func playSmartShuffle() async throws {
        let tracks = try await libraryService.smartShuffleQueue(targetSize: 50)
        guard !tracks.isEmpty else {
            Logger.player.info("Smart shuffle returned empty — library too small or no downloads offline")
            throw CassetteError.smartShuffleEmpty
        }

        // play(tracks:) resets isSmartShuffleActive via the new-queue check, so set the flag after.
        try await play(tracks: tracks, startIndex: 0)
        await MainActor.run { state.isSmartShuffleActive = true }

        Logger.player.info("Started Smart Shuffle session with \(tracks.count) tracks")
    }

    // MARK: - Instant Mix

    /// Starts an Instant Mix. When the caller can supply the seed TRACK (song seeds — every menu that
    /// offers "Instant Mix" on a song already holds it), that track starts immediately and the mix is
    /// built behind it. Album and artist seeds have no track in hand and keep the blocking path.
    ///
    /// This removes the wait rather than shortening it. Measured against a real AudioMuse server, the
    /// blocking path costs 36 s of silence — 12.8 s for the seed query, then 23 s for the fan-out —
    /// and the fan-out calls slow each other down by ~70% while they run.
    func playInstantMix(from seed: InstantMixSeed, startingWith seedTrack: DisplayableSong?) async throws {
        // `??` cannot host an async right-hand side (autoclosures are not concurrency-aware).
        let resolved: DisplayableSong?
        if let seedTrack {
            resolved = seedTrack
        } else {
            resolved = await starterTrack(for: seed)
        }
        guard let starter = resolved else {
            try await buildThenPlayInstantMix(from: seed)
            return
        }
        // Set BEFORE play(): starting a one-track queue re-evaluates auto-extend at once, and if
        // endless mode is already on from an earlier mix it would fire a library backfill into the
        // gap. The flag suppresses that until the mix itself has landed. Cleared inside appendInstantMix.
        isBuildingInstantMix = true
        do {
            try await play(tracks: [starter], startIndex: 0)
        } catch {
            isBuildingInstantMix = false
            throw error
        }
        Logger.player.info("[MIX-TIMING] seed '\(starter.id, privacy: .public)' playing immediately — mix building behind it")
        // The seed is already playing, so the audio background mode covers this on its own — the
        // assertion is the safety net for the user who hits pause while the mix is still building.
        Task { await BackgroundActivity.run("instant-mix") { await self.appendInstantMix(from: seed, behind: starter) } }
    }

    /// A track to start on when the caller had none. Album and artist mixes are offered from menus and
    /// headers that hold no song, so resolving one here — rather than at each call site — is what makes
    /// the instant start universal instead of song-only.
    ///
    /// Costs one or two catalogue calls, ~100 ms each measured, against a mix build of 30 s and more.
    /// Returning nil falls back to the blocking path, so a failure here is never worse than before.
    private func starterTrack(for seed: InstantMixSeed) async -> DisplayableSong? {
        switch seed {
        case .song:
            // Every song entry point already passes the track it was invoked on, and LibraryService
            // has no single-song fetch to fall back on.
            return nil
        case .album(let id):
            guard let song = (try? await libraryService.album(id: id))?.song?.first else { return nil }
            return DisplayableSong(from: song)
        case .artist(let id):
            guard let albumId = (try? await libraryService.artist(id: id))?.album?.first?.id,
                  let song = (try? await libraryService.album(id: albumId))?.song?.first
            else { return nil }
            return DisplayableSong(from: song)
        }
    }

    /// Builds the mix off the critical path and grafts it behind the already-playing seed.
    private func appendInstantMix(from seed: InstantMixSeed, behind seedTrack: DisplayableSong) async {
        // Whatever the outcome — appended, empty, abandoned, or thrown — the build is over, so stop
        // suppressing auto-extend. Safety net for the paths that return before the explicit clears below.
        defer { isBuildingInstantMix = false }
        do {
            let tracks = try await libraryService.instantMix(from: seed, count: 100)
            // The build takes tens of seconds. If the user moved on in the meantime, appending would
            // graft the mix onto an unrelated queue.
            guard await MainActor.run(body: { state.currentTrack?.id == seedTrack.id }) else {
                Logger.player.info("[INSTANT-MIX] built mix discarded — playback moved on during the build")
                return
            }
            let fresh = tracks.filter { $0.id != seedTrack.id }
            guard !fresh.isEmpty else {
                // A server with no similarity data (no AudioMuse, no Navidrome agent) answers empty.
                // Endless play still works there — it is built on listening history, discographies and
                // genres, not on the similarity endpoints — so fall through to it rather than leaving
                // the seed to play alone and stop. Clear the guard FIRST: here we *want* the immediate
                // re-evaluation to backfill the otherwise-lone seed.
                isBuildingInstantMix = false
                Logger.player.info("[INSTANT-MIX] no similarity data for seed — continuing with the library-based endless queue")
                await setAutoExtendEnabled(true)
                await MainActor.run {
                    toastService.show("No Instant Mix data for this track — continuing from your library.", style: .info, duration: 4.0)
                }
                return
            }
            await appendToQueue(fresh)
            // Mix is in the queue now; re-enable evaluation before turning auto-extend on. With ~100
            // tracks queued, the immediate re-evaluation sees plenty remaining and will not fetch —
            // the library backfill only fires later, once the mix is nearly spent.
            isBuildingInstantMix = false
            await setAutoExtendEnabled(true)
            Logger.player.info("[INSTANT-MIX] appended \(fresh.count, privacy: .public) tracks behind the seed (auto-extend on)")
        } catch {
            Logger.player.error("[INSTANT-MIX] background build failed: \(error, privacy: .public)")
            await MainActor.run { toastService.showError("Couldn't build the Instant Mix.") }
        }
    }

    /// The original blocking path: nothing plays until the whole mix is built. Still used for album and
    /// artist seeds, where there is no track to start from.
    private func buildThenPlayInstantMix(from seed: InstantMixSeed) async throws {
        // End-to-end latency, which is what the user waits through: the whole mix is built before a
        // single note plays. Split into build vs start so the two are attributable separately.
        let tStart = Date()
        let tracks = try await libraryService.instantMix(from: seed, count: 100)
        let buildMs = Int(Date().timeIntervalSince(tStart) * 1000)
        guard !tracks.isEmpty else {
            Logger.player.info("Instant Mix returned empty — no similarity data for seed")
            throw CassetteError.instantMixEmpty
        }
        let tPlay = Date()
        try await play(tracks: tracks, startIndex: 0)
        Logger.player.info("[MIX-TIMING] end-to-end=\(Int(Date().timeIntervalSince(tStart) * 1000), privacy: .public)ms (build=\(buildMs, privacy: .public)ms, start=\(Int(Date().timeIntervalSince(tPlay) * 1000), privacy: .public)ms)")
        // An Instant Mix is meant to be endless — turn on auto-extend so the queue keeps growing with
        // similar tracks (same mechanism as the automix) instead of running in circles on a short seed set.
        await setAutoExtendEnabled(true)
        Logger.player.info("Started Instant Mix with \(tracks.count) tracks (auto-extend on)")
    }

    func setVolume(_ volume: Float) async {
        let clamped = max(0, min(1, volume))
        audioPlayer.volume = clamped
        // Don't persist 0 — muting should not overwrite the saved restore volume.
        if clamped > 0 {
            UserDefaults.standard.set(clamped, forKey: "cassette.lastVolume")
        }
    }

    func replayGainSettingsDidChange() async {
        let (track, config) = await MainActor.run { (state.currentTrack, replayGainSettings.config) }
        await replayGainService?.apply(currentTrack: track, config: config)
    }

    func crossfadeSettingsDidChange() async {
        crossfadeConfig = await MainActor.run { crossfadeSettings.config }
    }

    func setAutoExtendEnabled(_ enabled: Bool) async {
        if enabled {
            // Endless play owns the queue order, so loop and shuffle are turned off rather than left
            // to conflict with it. Repeat especially: evaluateAutoExtend refuses to run while a loop
            // mode is active, which used to leave the infinity toggle lit and doing nothing. Clearing
            // them here makes the exclusivity visible in the UI instead of silent.
            // Done BEFORE the flag is set so setRepeatMode's own re-evaluation still sees it disabled
            // and cannot fire a fetch early.
            if await MainActor.run(body: { state.repeatMode != .off }) {
                await setRepeatMode(.off)
            }
            if await MainActor.run(body: { state.isShuffled }) {
                await toggleShuffle()
            }
        }
        await MainActor.run { state.isAutoExtendEnabled = enabled }
        UserDefaults.standard.set(enabled, forKey: Self.autoExtendUserDefaultsKey)
        if enabled {
            // State is updated before re-evaluation so the guards inside read fresh values.
            await evaluateAutoExtend()
        } else {
            await truncateExtensions()
        }
        Logger.player.info("Auto-extend \(enabled ? "enabled" : "disabled", privacy: .public)")
    }

    // MARK: - Auto-extend

    /// The pure trigger decision, factored out so it can be tested without driving the whole actor
    /// (same rationale as `truncationTarget`). The single-slot fetch guard stays in the caller: it is
    /// live runtime state, not a property of the queue.
    ///
    /// `isBuildingInstantMix` is the key addition — it holds back the fetch while a mix assembles
    /// behind its lone seed, so an already-enabled endless mode cannot backfill generic library
    /// tracks into the gap ahead of the real similar songs.
    nonisolated static func shouldAutoExtend(
        isEnabled: Bool,
        repeatMode: RepeatMode,
        hasRadio: Bool,
        isBuildingInstantMix: Bool,
        remaining: Int
    ) -> Bool {
        guard isEnabled, repeatMode == .off, !hasRadio, !isBuildingInstantMix else { return false }
        // Trigger threshold : 15 or fewer tracks remaining (including zero — covers singles
        // and starting from the last track of an album).
        return remaining <= 15
    }

    /// Reads queue position and fires a background fetch + append when ≤15 tracks remain.
    /// Called at the end of every startPlayback(). Guarded by a single-slot task to prevent
    /// parallel fetches when tracks advance rapidly. Errors are swallowed — natural queue
    /// end is the graceful fallback.
    private func evaluateAutoExtend() async {
        let (isEnabled, repeatMode, currentRadio, remaining, queueIds, seedTrackId) = await MainActor.run {
            let remaining = state.queue.count - state.currentIndex - 1
            return (state.isAutoExtendEnabled, state.repeatMode, state.currentRadio, remaining, Set(state.queue.map(\.id)), state.currentTrack?.id)
        }
        guard Self.shouldAutoExtend(
            isEnabled: isEnabled,
            repeatMode: repeatMode,
            hasRadio: currentRadio != nil,
            isBuildingInstantMix: isBuildingInstantMix,
            remaining: remaining
        ) else { return }
        guard autoExtendFetchTask == nil else { return }

        Logger.player.info("Auto-extend triggered: \(remaining) tracks remaining, fetching 50 similar")

        autoExtendFetchTask = Task { [libraryService, weak self] in
            defer { Task { await self?.clearAutoExtendFetchTask() } }
            do {
                // Seed on the track playing now: the extension is a sonic Instant Mix of it, with the
                // library heuristic as fallback. No current track (edge case) uses the heuristic directly.
                let tracks: [DisplayableSong]
                if let seedTrackId {
                    tracks = try await libraryService.endlessExtension(seedTrackId: seedTrackId, targetSize: 50, excludedIds: queueIds)
                } else {
                    tracks = try await libraryService.similarBackfillQueue(targetSize: 50, excludedIds: queueIds)
                }
                guard !tracks.isEmpty else {
                    Logger.player.debug("Auto-extend fetch returned empty — library exhausted or offline without downloads")
                    return
                }
                await self?.anchorOriginalQueueBoundaryIfNeeded()
                await self?.appendToQueue(tracks)
                Logger.player.info("Auto-extend appended \(tracks.count) tracks to queue")
            } catch {
                Logger.player.debug("Auto-extend fetch failed: \(error, privacy: .public)")
            }
        }
    }

    private func clearAutoExtendFetchTask() {
        autoExtendFetchTask = nil
    }

    /// Records the current queue count as the boundary between user-intentional and
    /// auto-extended tracks. No-op if the boundary is already set (first extend wins).
    private func anchorOriginalQueueBoundaryIfNeeded() async {
        let alreadySet = await MainActor.run { state.originalQueueEndIndex != nil }
        guard !alreadySet else { return }
        let queueCount = await MainActor.run { state.queue.count }
        await MainActor.run { state.originalQueueEndIndex = queueCount }
        Logger.player.debug("Auto-extend boundary anchored at \(queueCount)")
    }

    /// New queue count after dropping the auto-extended tail, or `nil` when there is nothing to drop.
    ///
    /// Turning endless play off means "stop growing my queue", and the tracks it already grew are just
    /// as unwanted as the ones it would have added next — so they go too. The one thing never removed is
    /// the track currently playing: yanking it out mid-listen would stop the music on a toggle that says
    /// nothing about stopping. So inside the original zone the whole tail goes; inside the extended zone
    /// the current track survives as the new last entry and playback ends naturally after it.
    nonisolated static func truncationTarget(boundary: Int?, currentIndex: Int, queueCount: Int) -> Int? {
        guard let boundary, boundary < queueCount else { return nil }
        let target = currentIndex < boundary ? boundary : currentIndex + 1
        return target < queueCount ? target : nil
    }

    /// Drops the tracks auto-extend appended, keeping whatever is playing right now.
    private func truncateExtensions() async {
        let (boundary, currentIndex, queueCount) = await MainActor.run {
            (state.originalQueueEndIndex, state.currentIndex, state.queue.count)
        }
        guard let target = Self.truncationTarget(boundary: boundary, currentIndex: currentIndex, queueCount: queueCount) else {
            // Still clear the boundary: with endless play off it no longer marks anything, and leaving it
            // set would make a later re-enable anchor onto a stale index.
            await MainActor.run { state.originalQueueEndIndex = nil }
            return
        }
        await MainActor.run {
            state.queue = Array(state.queue[0..<target])
            state.originalQueueEndIndex = nil
        }
        Logger.player.info("Auto-extend tail truncated to \(target) of \(queueCount) (currentIndex=\(currentIndex), boundary=\(boundary ?? -1))")
    }

    // MARK: - Pause / Resume

    func pause() async {
        cancelFadeTasks()
        finalizePlaySegment()
        audioPlayer.pause()
        #if os(iOS)
        sessionActivationRetryTask?.cancel()
        sessionActivationRetryTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        await MainActor.run { state.playbackState = .paused }
        await pushPositionSnapshot(rate: 0.0)
        stopProgressTimer()
        stopPositionSaveTimer()
        await saveSession()
        let pauseTrack = await MainActor.run { state.currentTrack }
        if let ws = widgetSyncService {
            Task { [weak ws] in await ws?.onPlayStateChanged(isPlaying: false, currentSong: pauseTrack) }
        }
    }

    func resume() async {
        // User explicitly pressed play — cancel any pending restore auto-pause and lift eof guard.
        restorePauseTask?.cancel()
        restorePauseTask = nil
        if isMutedForRestore {
            audioPlayer.volume = restoredVolume
            isMutedForRestore = false
        }
        isRestoringSession = false
        #if os(iOS)
        configureAudioSessionIfNeeded()
        #endif
        // Lazily start the accumulator for session-restored tracks that resume for the first time.
        if trackPlayStartDate == nil { trackPlayStartDate = Date() }
        if currentPlaySegmentStart == nil { currentPlaySegmentStart = Date() }

        // Resuming after the queue ended (stopped cleanly at the end, repeat off): restart from track 0, NOT
        // the last track — replaying it would hit EOF immediately and re-stop (the mini-loop). A normal mid-track
        // pause leaves this flag false and falls through to the regular resume below.
        if stoppedAtEndOfQueue {
            stoppedAtEndOfQueue = false
            pendingRestoreInfo = nil
            let queue = await MainActor.run { state.queue }
            if !queue.isEmpty {
                try? await play(tracks: queue, startIndex: 0)
                return
            }
        }

        // Cold-restore path: session activation was deferred at launch, so the player was never
        // started. Start fresh now that the user has explicitly triggered playback.
        if audioPlayer.state == .ready, let source = currentSource {
            if let info = pendingRestoreInfo, info.pause {
                pendingRestoreInfo = (seekTime: info.seekTime, pause: false)
            }
            // Re-resolve through MediaResolver — the stored source was resolved at
            // launch and may be hours old; a stale stream URL fails silently. This
            // mirrors the always-re-resolve invariant every other playback start holds.
            let freshSource = await refreshedColdStartSource() ?? source
            currentSource = freshSource
            audioPlayer.play(url: freshSource.url, headers: freshSource.customHeaders)
        } else {
            audioPlayer.resume()
        }
        await MainActor.run { state.playbackState = .playing }
        await pushPositionSnapshot(rate: 1.0)
        startProgressTimer()
        startPositionSaveTimer()
        let resumeTrack = await MainActor.run { state.currentTrack }
        if let ws = widgetSyncService {
            Task { [weak ws] in await ws?.onPlayStateChanged(isPlaying: true, currentSong: resumeTrack) }
        }
    }

    /// Fresh download > cache > stream resolution for the cold-start resume path.
    /// Returns nil (caller keeps the stored source) when the track or server is
    /// unknown or resolution fails — local copies resolve without any network.
    private func refreshedColdStartSource() async -> MediaSource? {
        guard let track = await MainActor.run(body: { state.currentTrack }),
              let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) else { return nil }
        do {
            return try await mediaResolver.resolve(songId: track.id, serverId: serverId)
        } catch {
            Logger.player.warning("[RESTORE] cold-start re-resolve failed — keeping stored source: \(error, privacy: .public)")
            return nil
        }
    }

    func togglePlayPause() async {
        let isPlaying = await MainActor.run { state.playbackState == .playing }
        if isPlaying { await pause() } else { await resume() }
    }

    // MARK: - Stop

    func stop() async {
        cancelPendingScrobble()
        cancelPendingCacheDownload()
        cancelPendingPrefetch()
        cancelFadeTasks()
        stopProgressTimer()
        stopPositionSaveTimer()
        restorePauseTask?.cancel()
        restorePauseTask = nil
        if isMutedForRestore {
            audioPlayer.volume = restoredVolume
            isMutedForRestore = false
        }
        liveStreamStallTask?.cancel()
        liveStreamStallTask = nil
        audioPlayer.stop()
        #if os(iOS)
        sessionActivationRetryTask?.cancel()
        sessionActivationRetryTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        accumulatedPlayedSeconds = 0
        currentPlaySegmentStart = nil
        trackPlayStartDate = nil
        await replayGainService?.resetGain()
        currentSource = nil
        pendingRestoreInfo = nil
        isRestoringSession = false
        await MainActor.run {
            state.playbackState = .idle
            state.currentTrack = nil
            state.currentRadio = nil
            state.isSmartShuffleActive = false
            state.originalQueueEndIndex = nil
            state.queue = []
            state.position = 0
            state.duration = 0
        }
    }

    // MARK: - Seek

    func seek(to position: TimeInterval) async {
        // Reject malformed targets (NaN/inf). A scrubber drag against a zero-width track produces NaN, which
        // would trap in the AudioStreaming engine's Int64(time / duration). The single chokepoint for every
        // seek caller (UI, lyrics, lock screen). A malformed seek is a silent no-op — NOT a jump to zero.
        guard position.isFinite else {
            Logger.player.warning("seek ignored — non-finite target")
            return
        }
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("seek ignored — live stream mode")
            return
        }
        // Cancel any active fade and restore volume — repositioning during a fade
        // would otherwise leave the player stuck at a low volume.
        cancelFadeTasks()
        // Finalize the current segment and start a fresh one so that only
        // audio actually heard after the seek point is counted in played time.
        if currentPlaySegmentStart != nil {
            finalizePlaySegment()
            currentPlaySegmentStart = Date()
        }
        audioPlayer.seek(to: position)
        await MainActor.run { state.position = position }
        await pushPositionSnapshot()
    }

    // MARK: - Skip

    func skipToNext() async throws {
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("skipToNext ignored — live stream mode")
            return
        }
        let (queue, currentIndex, repeatMode) = await MainActor.run {
            (state.queue, state.currentIndex, state.repeatMode)
        }
        let nextIndex = currentIndex + 1
        Logger.player.info("[TRANSITION] skipToNext: currentIndex=\(currentIndex) nextIndex=\(nextIndex) queueCount=\(queue.count)")

        if nextIndex < queue.count {
            let next = queue[nextIndex]
            Logger.player.info("[TRANSITION] skipToNext → track id=\(next.id, privacy: .public) title=\(next.title, privacy: .public)")
            try await play(tracks: queue, startIndex: nextIndex)
        } else if repeatMode == .all {
            Logger.player.info("[TRANSITION] skipToNext → wrap-around (repeatAll), restarting queue from index 0")
            try await play(tracks: queue, startIndex: 0)
        } else {
            await pauseAtEndOfQueue()
        }
    }

    func skipToPrevious() async throws {
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("skipToPrevious ignored — live stream mode")
            return
        }
        let (queue, currentIndex, position) = await MainActor.run {
            (state.queue, state.currentIndex, state.position)
        }

        // < 3 s into the track: go back; at track 0 or after 3 s: restart current.
        if position >= 3 || currentIndex == 0 {
            await seek(to: 0)
        } else {
            try await play(tracks: queue, startIndex: currentIndex - 1)
        }
    }

    // MARK: - Queue management

    func setRepeatMode(_ mode: RepeatMode) async {
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("setRepeatMode ignored — live stream mode")
            return
        }
        let previousMode = await MainActor.run { state.repeatMode }
        await MainActor.run { state.repeatMode = mode }
        // Activating any loop mode while in the original zone truncates the auto-extended tail.
        if previousMode == .off && mode != .off {
            await truncateExtensions()
        }
        // Deactivating loop may newly satisfy the auto-extend repeat guard — re-evaluate.
        if previousMode != .off && mode == .off {
            await evaluateAutoExtend()
        }
        await saveSession()
    }

    func toggleShuffle() async {
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("toggleShuffle ignored — live stream mode")
            return
        }
        let isCurrentlyShuffled = await MainActor.run { state.isShuffled }
        if isCurrentlyShuffled {
            await restoreOriginalQueueOrder()
            await MainActor.run { state.isShuffled = false }
        } else {
            await shuffleUpNext()
            await MainActor.run { state.isShuffled = true }
        }
        await saveSession()
    }

    private func shuffleUpNext() async {
        let (queue, currentIndex) = await MainActor.run { (state.queue, state.currentIndex) }
        originalQueueOrder = queue
        guard currentIndex + 1 < queue.count else { return }
        let head = Array(queue[...currentIndex])
        let shuffled = Array(queue[(currentIndex + 1)...]).shuffled()
        await MainActor.run { state.queue = head + shuffled }
    }

    private func restoreOriginalQueueOrder() async {
        guard let original = originalQueueOrder,
              let currentTrack = await MainActor.run(body: { state.currentTrack }),
              let restoredIndex = original.firstIndex(where: { $0.id == currentTrack.id })
        else { return }
        await MainActor.run {
            state.queue = original
            state.currentIndex = restoredIndex
        }
        originalQueueOrder = nil
    }

    func appendToQueue(_ tracks: [DisplayableSong]) async {
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("appendToQueue ignored — live stream mode")
            return
        }
        await MainActor.run { state.queue.append(contentsOf: tracks) }
        await saveSession()
    }

    func playNext(_ songs: [DisplayableSong]) async {
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("playNext ignored — live stream mode")
            return
        }
        let (queue, currentIndex) = await MainActor.run { (state.queue, state.currentIndex) }
        if queue.isEmpty {
            do {
                try await play(tracks: songs, startIndex: 0)
            } catch {
                Logger.player.error("[PLAYBACK] playNext: play() failed on empty queue: \(error, privacy: .public)")
            }
        } else {
            let insertAt = min(currentIndex + 1, queue.count)
            await MainActor.run { state.queue.insert(contentsOf: songs, at: insertAt) }
            Logger.player.info("Inserted \(songs.count) song(s) at queue position \(insertAt)")
            await saveSession()
            if !songs.isEmpty {
                await presentQueueConfirmation(
                    String(localized: "\(songs.count) songs playing next"),
                    coverArtId: songs.first?.coverArtId
                )
            }
        }
        // Empty-queue Play Next falls back to play() above and starts playback immediately,
        // which is its own visible feedback — no confirmation toast there, matching Play.
    }

    func playNext(_ song: DisplayableSong) async {
        await playNext([song])
    }

    func addToQueue(_ songs: [DisplayableSong]) async {
        await appendToQueue(songs)
        // appendToQueue is also the silent leaf for background auto-extend, so the confirmation
        // lives here on the user-facing path. Re-check live stream: appendToQueue no-ops on radio.
        guard !songs.isEmpty,
              await MainActor.run(body: { !state.isLiveStream }) else { return }
        await presentQueueConfirmation(
            String(localized: "\(songs.count) songs added to queue"),
            coverArtId: songs.first?.coverArtId
        )
    }

    func addToQueue(_ song: DisplayableSong) async {
        await addToQueue([song])
    }

    /// Presents an enqueue confirmation toast on the main actor. Callers guard against empty
    /// batches (failed lazy loads) and live-stream mode so those no-op paths stay silent.
    private func presentQueueConfirmation(_ message: String, coverArtId: String? = nil) async {
        await MainActor.run { toastService.showConfirmation(message, coverArtId: coverArtId) }
    }

    func removeFromQueue(at index: Int) async {
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("removeFromQueue ignored — live stream mode")
            return
        }
        let (queueCount, currentIndex, isShuffled) = await MainActor.run {
            (state.queue.count, state.currentIndex, state.isShuffled)
        }
        guard index >= 0, index < queueCount else { return }
        guard index != currentIndex else {
            Logger.player.warning("removeFromQueue: index \(index) is current track — ignored")
            return
        }
        await MainActor.run {
            state.queue.remove(at: index)
            if index < state.currentIndex { state.currentIndex -= 1 }
        }
        if isShuffled { originalQueueOrder = nil }
        let newIdx = await MainActor.run { state.currentIndex }
        Logger.player.info("Removed track at \(index), currentIndex now \(newIdx)")
        await saveSession()
    }

    func moveInQueue(fromIndex: Int, toIndex: Int) async {
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("moveInQueue ignored — live stream mode")
            return
        }
        let (queueCount, currentIndex, isShuffled) = await MainActor.run {
            (state.queue.count, state.currentIndex, state.isShuffled)
        }
        guard fromIndex >= 0, fromIndex < queueCount else { return }
        guard toIndex >= 0, toIndex <= queueCount else { return }
        guard fromIndex != toIndex else { return }
        await MainActor.run {
            // Replicates Array.move(fromOffsets:toOffset:) semantics without SwiftUI:
            // element ends up at toIndex-1 when fromIndex < toIndex, or toIndex otherwise.
            let song = state.queue.remove(at: fromIndex)
            let dest = fromIndex < toIndex ? toIndex - 1 : toIndex
            state.queue.insert(song, at: dest)
            if fromIndex == currentIndex {
                state.currentIndex = fromIndex < toIndex ? toIndex - 1 : toIndex
            } else if fromIndex < currentIndex && toIndex > currentIndex {
                state.currentIndex -= 1
            } else if fromIndex > currentIndex && toIndex <= currentIndex {
                state.currentIndex += 1
            }
        }
        if isShuffled { originalQueueOrder = nil }
        let newIdx = await MainActor.run { state.currentIndex }
        Logger.player.info("Moved track \(fromIndex)→\(toIndex), currentIndex now \(newIdx)")
        await saveSession()
    }

    // MARK: - Session persistence

    /// Lightweight position-only flush — called from scenePhase .inactive on iOS
    /// to protect the current position against a fast process kill.
    func saveCurrentPosition() async {
        let pos = audioPlayer.progress
        guard pos > 0 else { return }
        await sessionService.savePosition(pos)
    }

    private func saveSession() async {
        let snapshot = await MainActor.run {
            SessionPayload(
                currentIndex: state.currentIndex,
                currentPosition: state.position,
                queue: state.queue,
                currentTrack: state.currentTrack,
                repeatMode: state.repeatMode
            )
        }
        await sessionService.save(playerState: snapshot)
    }

    func restoreSession() async {
        guard let data = await sessionService.loadRestoredSession() else { return }

        let track = data.queue[data.currentIndex]
        await MainActor.run {
            state.queue = data.queue
            state.currentIndex = data.currentIndex
            state.currentTrack = track
            state.currentRadio = nil
            state.position = data.currentPosition
            state.duration = data.currentTrackDuration
            state.repeatMode = data.repeatMode
            state.playbackState = .paused
        }

        // If the saved session was parked at the END of the last track (the queue had finished, repeat off),
        // mark it so resume() restarts from track 0 instead of replaying the last track's tail and immediately
        // hitting EOF — a phantom transition at cold start. pauseAtEndOfQueue parks position exactly at duration,
        // and a mid-track pause leaves position < duration, so the tight epsilon distinguishes the two.
        if data.repeatMode == .off,
           data.currentIndex == data.queue.count - 1,
           data.currentTrackDuration > 0,
           data.currentPosition >= data.currentTrackDuration - 0.1 {
            stoppedAtEndOfQueue = true
            Logger.player.info("[RESTORE] session was parked at end of queue — resume will restart from track 0")
        }

        await prepareCurrentTrackForRestoration(track: track, position: data.currentPosition)
        Logger.player.info("Session restored: \(data.queue.count) tracks, index \(data.currentIndex), pos=\(data.currentPosition, format: .fixed(precision: 1))s")
    }

    private func prepareCurrentTrackForRestoration(track: DisplayableSong, position: TimeInterval) async {
        // Set the guard immediately — before any await — so handleNetworkRestored() cannot
        // race in during mediaResolver.resolve() and trigger a second play() call that would
        // consume pendingRestoreInfo before the deferred seek is applied.
        isRestoringSession = true

        guard let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) else {
            Logger.player.warning("Session restore: no active server, skipping player prep")
            isRestoringSession = false
            return
        }

        let source: MediaSource
        do {
            source = try await mediaResolver.resolve(songId: track.id, serverId: serverId)
        } catch {
            Logger.player.error("Session restore: failed to resolve media — \(error)")
            await MainActor.run { state.isPlaybackAvailable = false }
            isRestoringSession = false
            return
        }

        stopProgressTimer()
        currentSource = source
        // Seek to saved position on first play; pause flag cleared in resume() when user
        // explicitly starts playback, or kept if user hasn't tapped play yet.
        pendingRestoreInfo = (seekTime: position, pause: true)

        // Apply ReplayGain after restore state is fully committed (no suspension between
        // currentSource and pendingRestoreInfo above). globalGain is set on the EQ node
        // and takes effect when audio flows, so applying while paused is correct.
        let config = await MainActor.run { replayGainSettings.config }
        await replayGainService?.apply(track: track, config: config)
        Logger.player.debug("[RESTORE] ReplayGain applied for '\(track.title, privacy: .public)'")

        // Session activation is intentionally deferred to the first user-triggered play.
        // Activating here would grab the audio route from other devices (e.g. Mac+AirPods)
        // before the user has indicated intent to listen.

        await MainActor.run { state.isPlaybackAvailable = true }
        Logger.player.info("Session restore: '\(track.title)' queued at \(position, format: .fixed(precision: 1))s (playback deferred)")

        // Populate MPNowPlayingInfoCenter in paused state so lock screen controls appear
        // immediately when the user resumes — resume() only sends a position-only update
        // which would start from an empty dict otherwise.
        let duration = await MainActor.run { state.duration }
        let artworkURL = await resolveArtworkURL(for: track)
        let artworkHeaders: [String: String]
        do {
            artworkHeaders = try await serverService.activeCredentials().customHeaders
        } catch {
            Logger.player.warning("[CREDENTIALS] activeCredentials failed, using empty headers: \(error, privacy: .public)")
            artworkHeaders = [:]
        }
        await nowPlayingService?.update(with: NowPlayingSnapshot(
            title: track.title,
            artist: track.artist,
            album: track.albumName,
            duration: duration,
            position: position,
            playbackRate: 0.0,
            artworkURL: artworkURL,
            artworkHeaders: artworkHeaders,
            coverArtId: track.coverArtId,
            isLiveStream: false,
            radioStationName: nil,
            songId: track.id
        ))
        isRestoringSession = false
    }

    func handleNetworkRestored() async {
        // Don't race with an in-progress session restore; prepareCurrentTrackForRestoration
        // sets isRestoringSession before its first await so this check is reliable.
        guard !isRestoringSession else {
            Logger.player.info("Network restored — session restore already in progress, skipping re-prepare")
            return
        }
        let (isAvailable, track, position) = await MainActor.run {
            (state.isPlaybackAvailable, state.currentTrack, state.position)
        }
        guard !isAvailable, let track else { return }
        Logger.player.info("Network restored — re-preparing '\(track.title)'")
        await prepareCurrentTrackForRestoration(track: track, position: position)
    }

    // MARK: - Position save timer

    private func startPositionSaveTimer() {
        stopPositionSaveTimer()
        positionSaveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                guard !isRestoringSession else { continue }
                // Position-only update — queue/track/mode already saved at each state change. Check the
                // actor-local seekability first (no MainActor hop): a non-seekable stream can't restore a
                // position, so skip the hop entirely rather than reading state only to discard it.
                guard audioPlayer.isSeekable else { continue }
                let (isPlaying, pos) = await MainActor.run {
                    (state.playbackState == .playing, state.position)
                }
                guard isPlaying else { continue }
                await sessionService.savePosition(pos)
            }
        }
    }

    private func stopPositionSaveTimer() {
        positionSaveTask?.cancel()
        positionSaveTask = nil
    }

    // MARK: - Progress timer

    private func startProgressTimer() {
        stopProgressTimer()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { break }
                let progress = self.audioPlayer.progress
                let audioDuration = self.audioPlayer.duration
                await MainActor.run {
                    let cur = self.state.duration
                    let clamped = cur > 0 ? min(progress, cur) : progress
                    self.state.position = clamped
                    // Refine duration when AudioStreaming parses the real value from the stream.
                    if audioDuration > 0, abs(audioDuration - cur) > 0.5 {
                        self.state.duration = audioDuration
                    }
                }
                await self.periodicNowPlayingPush(elapsed: progress)
                await self.checkScrobbleThreshold()
                await self.checkPrefetchThreshold()
                await self.checkFadeOutThreshold()
            }
        }
    }

    private func stopProgressTimer() {
        progressTask?.cancel()
        progressTask = nil
    }

    // MARK: - Scrobble

    /// Cancels any pending playing-now task. Called when switching tracks,
    /// switching to radio, or stopping. Safe to call when no task is scheduled.
    private func cancelPendingScrobble() {
        playingNowTask?.cancel()
        playingNowTask = nil
    }

    private func checkScrobbleThreshold() async {
        guard let song = await MainActor.run(body: { state.currentTrack }) else { return }
        fireScrobbleIfThresholdMet(song: song)
    }

    // Synchronous split required by Swift 6: mutating a struct property (`detector`)
    // is only legal in a non-async actor method (no suspension points → no reentrancy window).
    private func fireScrobbleIfThresholdMet(song: DisplayableSong) {
        let duration = song.duration
        let songId = song.id
        let segmentContrib = currentPlaySegmentStart.map { Date().timeIntervalSince($0) } ?? 0
        let accumulated = accumulatedPlayedSeconds + segmentContrib
        guard detector.check(duration: duration, accumulated: accumulated) else { return }
        let startDate = trackPlayStartDate ?? Date()
        Task { [libraryService] in
            await libraryService.scrobble(songId: songId, submission: true)
        }
        Task { [listenBrainzService] in
            await listenBrainzService.notifyScrobbleThreshold(song: song, startDate: startDate)
        }
    }

    private func cancelPendingCacheDownload() {
        cacheDownloadTask?.cancel()
        cacheDownloadTask = nil
    }

    // MARK: - Crossfade prefetch

    private func cancelPendingPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchScheduled = false
    }

    nonisolated static func shouldSchedulePrefetch(crossfadeDuration: Double, remaining: Double) -> Bool {
        guard crossfadeDuration > 0 else { return false }
        return remaining <= crossfadeDuration + 15.0
    }

    nonisolated static func shouldProceedWithPrefetch(isExpensive: Bool, allowCellular: Bool) -> Bool {
        if isExpensive && !allowCellular { return false }
        return true
    }

    private func checkPrefetchThreshold() async {
        guard !prefetchScheduled else { return }
        // Snapshot only the scalars each tick — never copy the whole `state.queue` array (it can be large
        // and this runs every 500ms). The next-song element is read on MainActor only when we actually
        // proceed, in a single hop alongside the server id (also trimming one MainActor round-trip).
        let (currentIndex, duration, position) = await MainActor.run {
            (state.currentIndex, state.duration, state.position)
        }
        guard duration > 0 else { return }
        let remaining = duration - position
        guard PlayerService.shouldSchedulePrefetch(crossfadeDuration: crossfadeConfig.duration, remaining: remaining) else { return }

        let nextIndex = currentIndex + 1
        let resolved: (nextSong: DisplayableSong, serverId: UUID)? = await MainActor.run {
            guard state.queue.indices.contains(nextIndex),
                  let serverId = serverService.state.activeServer?.id else { return nil }
            return (state.queue[nextIndex], serverId)
        }
        guard let resolved else { return }

        prefetchScheduled = true
        Logger.player.debug("[PREFETCH] scheduling prefetch for '\(resolved.nextSong.title, privacy: .public)' (remaining=\(String(format: "%.1f", remaining))s)")
        await prefetchNextTrack(nextSong: resolved.nextSong, serverId: resolved.serverId)
    }

    private func prefetchNextTrack(nextSong: DisplayableSong, serverId: UUID) async {
        let songId = nextSong.id

        if await audioStreamCache.cachedURL(forSongId: songId, serverId: serverId) != nil {
            Logger.player.debug("[PREFETCH] '\(songId, privacy: .public)' already cached — skip")
            return
        }
        if await downloadService.isDownloaded(songId: songId, serverId: serverId) {
            Logger.player.debug("[PREFETCH] '\(songId, privacy: .public)' already downloaded — skip")
            return
        }

        let (isExpensive, allowCellular) = await MainActor.run {
            (serverService.state.isExpensive, cacheSettings.cacheOverCellular)
        }
        guard PlayerService.shouldProceedWithPrefetch(isExpensive: isExpensive, allowCellular: allowCellular) else {
            Logger.player.debug("[PREFETCH] '\(songId, privacy: .public)' skipped — cellular guard")
            return
        }

        guard let streamURL = (try? await serverService.makeSwiftSonicClient())?.streamURL(
            id: songId,
            maxBitRate: 0,
            format: nil
        ) else {
            Logger.player.debug("[PREFETCH] '\(songId, privacy: .public)' no stream URL — skip")
            return
        }

        let customHeaders: [String: String]
        do {
            customHeaders = try await serverService.activeCredentials().customHeaders
        } catch {
            Logger.player.debug("[PREFETCH] '\(songId, privacy: .public)' credentials unavailable — skip")
            return
        }

        prefetchTask = Task { [prefetchSession, weak self] in
            guard !Task.isCancelled else { return }
            do {
                try await self?.downloadAndCache(
                    songId: songId,
                    serverId: serverId,
                    streamURL: streamURL,
                    customHeaders: customHeaders,
                    using: prefetchSession
                )
                Logger.player.info("[PREFETCH] '\(songId, privacy: .public)' prefetch complete")
            } catch {
                Logger.player.debug("[PREFETCH] '\(songId, privacy: .public)' prefetch failed: \(error, privacy: .public)")
            }
        }
    }

    // MARK: - Crossfade fade engine

    private func cancelFadeTasks() {
        let wasActive = fadeOutTask != nil || fadeInTask != nil || isFadingOut
        fadeOutTask?.cancel()
        fadeOutTask = nil
        fadeInTask?.cancel()
        fadeInTask = nil
        isFadingOut = false
        if wasActive {
            let vol = restoredVolume
            audioPlayer.volume = vol
            Logger.crossfade.info("fade cancelled — volume restored to \(vol, format: .fixed(precision: 2))")
        }
    }

    /// Returns true when the current and next track form a gapless pair (same album, consecutive track numbers).
    /// Nil albumId or track number → not a pair, so crossfade proceeds.
    nonisolated static func isGaplessPair(
        currentAlbumId: String?,
        currentTrackNumber: Int?,
        nextAlbumId: String?,
        nextTrackNumber: Int?
    ) -> Bool {
        guard let cAlbum = currentAlbumId,
              let nAlbum = nextAlbumId,
              let cTrack = currentTrackNumber,
              let nTrack = nextTrackNumber else { return false }
        return cAlbum == nAlbum && nTrack == cTrack + 1
    }

    nonisolated static func shouldStartFadeOut(
        crossfadeDuration: Double,
        remaining: Double,
        hasNext: Bool,
        trackDuration: Double,
        repeatOne: Bool = false
    ) -> Bool {
        guard crossfadeDuration > 0, hasNext else { return false }
        // Repeat-one loops the same track on the same player; there's no second source
        // to mix into, so a fade-out would just produce a silent gap.
        guard !repeatOne else { return false }
        // Skip on short tracks to avoid starting a fade immediately after playback begins.
        guard trackDuration > 2 * crossfadeDuration else { return false }
        return remaining > 0 && remaining <= crossfadeDuration
    }

    private func checkFadeOutThreshold() async {
        guard !isFadingOut else { return }
        guard crossfadeConfig.duration > 0 else { return }
        let (duration, position, isPlaying, currentIndex, queueCount, repeatMode, title) = await MainActor.run {
            (state.duration, state.position, state.playbackState == .playing,
             state.currentIndex, state.queue.count, state.repeatMode,
             state.currentTrack?.title ?? "?")
        }
        guard isPlaying, duration > 0 else { return }
        let remaining = duration - position
        let D = crossfadeConfig.duration
        let hasNext = currentIndex + 1 < queueCount || repeatMode != .off

        // Log skip reasons only while inside the crossfade window (avoids per-tick spam).
        if remaining > 0 && remaining <= D {
            if !hasNext {
                Logger.crossfade.debug("skip — no-next track (remaining=\(String(format:"%.2f",remaining))s)")
            } else if repeatMode == .one {
                Logger.crossfade.debug("skip — repeat-one (track='\(title, privacy: .public)')")
            } else if duration <= 2 * D {
                Logger.crossfade.debug("skip — short track (duration=\(String(format:"%.1f",duration))s, 2D=\(String(format:"%.1f",2*D))s)")
            }
        }

        guard PlayerService.shouldStartFadeOut(
            crossfadeDuration: D,
            remaining: remaining,
            hasNext: hasNext,
            trackDuration: duration,
            repeatOne: repeatMode == .one
        ) else { return }

        if crossfadeConfig.disableForGapless {
            let (currentSong, nextSong): (DisplayableSong?, DisplayableSong?) = await MainActor.run {
                let nextIndex = state.currentIndex + 1
                return (state.currentTrack, state.queue.indices.contains(nextIndex) ? state.queue[nextIndex] : nil)
            }
            if let current = currentSong, let next = nextSong,
               PlayerService.isGaplessPair(
                   currentAlbumId: current.albumId,
                   currentTrackNumber: current.trackNumber,
                   nextAlbumId: next.albumId,
                   nextTrackNumber: next.trackNumber
               ) {
                Logger.crossfade.debug("skip — gapless pair (track='\(title, privacy: .public)')")
                return
            }
        }

        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType }
        guard !PlayerService.isProblematicRoute(portTypes: outputs) else {
            Logger.crossfade.debug("skip — AirPlay route (track='\(title, privacy: .public)')")
            return
        }
        #endif

        isFadingOut = true
        let userVol = restoredVolume
        Logger.crossfade.info("fade-out START — track='\(title, privacy: .public)' remaining=\(String(format:"%.2f",remaining))s D=\(String(format:"%.1f",D))s targetVol=\(String(format:"%.2f",userVol))->0")
        performFadeOut(duration: remaining)
    }

    nonisolated static func crossfadeVolume(base: Float, progress: Double, phase: CrossfadePhase) -> Float {
        let p = max(0.0, min(1.0, progress))
        switch phase {
        case .fadeOut: return base * Float(cos(p * .pi / 2))
        case .fadeIn:  return base * Float(sin(p * .pi / 2))
        }
    }

    private func performFadeOut(duration: Double) {
        let startVolume = audioPlayer.volume
        let fadeDuration = max(duration, 0.05)
        fadeOutTask = Task { [weak self] in
            guard let self else { return }
            let startTime = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let progress = min(elapsed / fadeDuration, 1.0)
                self.audioPlayer.volume = PlayerService.crossfadeVolume(base: startVolume, progress: progress, phase: .fadeOut)
                if progress >= 1.0 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    /// Fades the player volume in over `duration` seconds.
    /// Re-reads `restoredVolume` each tick so a mid-fade slider drag is tracked immediately.
    private func performFadeIn(duration: Double) {
        let fadeDuration = max(duration, 0.05)
        fadeInTask = Task { [weak self] in
            guard let self else { return }
            Logger.crossfade.info("fade-in START vol=0->target=\(self.restoredVolume, format: .fixed(precision: 2))")
            let startTime = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let progress = min(elapsed / fadeDuration, 1.0)
                let target = self.restoredVolume
                self.audioPlayer.volume = PlayerService.crossfadeVolume(base: target, progress: progress, phase: .fadeIn)
                if progress >= 1.0 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            if !Task.isCancelled {
                let final = self.restoredVolume
                self.audioPlayer.volume = final
                Logger.crossfade.info("fade-in DONE vol=\(final, format: .fixed(precision: 2))")
            }
        }
    }

    #if os(iOS)
    /// Returns true for routes where crossfade volume ramping sounds wrong or causes artefacts.
    /// `.airPlay` is the initial entry; add `.bluetoothA2DP` or `.carAudio` here when needed.
    nonisolated static func isProblematicRoute(portTypes: [AVAudioSession.Port]) -> Bool {
        let problematic: Set<AVAudioSession.Port> = [.airPlay]
        return portTypes.contains(where: { problematic.contains($0) })
    }

    /// Returns true when the route outputs represent a personal listening device whose
    /// disconnection must auto-pause playback (never continue on the built-in speaker).
    /// Includes AirPlay/CarPlay so their disconnects keep today's pause behavior.
    nonisolated static func isPersonalAudioRoute(portTypes: [AVAudioSession.Port]) -> Bool {
        let personal: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .airPlay, .carAudio
        ]
        return portTypes.contains(where: { personal.contains($0) })
    }
    #endif

    // MARK: - Play-time accumulator

    /// Closes the current play segment and adds its duration to the accumulator.
    /// Safe to call when paused (currentPlaySegmentStart == nil) — no-op in that case.
    private func finalizePlaySegment() {
        guard let start = currentPlaySegmentStart else { return }
        accumulatedPlayedSeconds += Date().timeIntervalSince(start)
        currentPlaySegmentStart = nil
    }

    /// Resets all per-track accumulator state for the next track.
    /// Call immediately after recordCurrentTrackPlayback() in every transition site.
    private func resetTrackAccumulator(isPlaying: Bool) {
        accumulatedPlayedSeconds = 0
        trackPlayStartDate = Date()
        currentPlaySegmentStart = isPlaying ? Date() : nil
        detector.reset()
    }

    // MARK: - Stats recording

    private func recordCurrentTrackPlayback(trigger: String = "unknown") async {
        guard let song = await MainActor.run(body: { state.currentTrack }),
              let startDate = trackPlayStartDate else { return }
        guard let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) else { return }

        // Tally the in-progress segment without permanently mutating accumulatedPlayedSeconds
        // (the caller resets the accumulator immediately after this call).
        let segmentContrib = currentPlaySegmentStart.map { Date().timeIntervalSince($0) } ?? 0
        let durationListened = accumulatedPlayedSeconds + segmentContrib
        guard durationListened >= 30 else {
            Logger.player.debug("[STATS] Skip — durationListened=\(durationListened, format: .fixed(precision: 1))s < 30s for '\(song.title, privacy: .public)'")
            return
        }

        let trackDuration = await MainActor.run { state.duration }
        let dto = PlaybackEventDTO(
            trackId: song.id,
            trackTitle: song.title,
            albumId: song.albumId,
            albumTitle: song.albumName,
            artistId: song.artistId,
            artistName: song.artist ?? "",
            genre: song.genre,
            timestamp: startDate,
            durationListened: durationListened,
            trackDuration: trackDuration,
            wasCompleted: wasTrackCompletedNaturally,
            serverId: serverId.uuidString
        )
        await statsService.recordPlayback(dto, trigger: trigger)
        let artistIdForLog = song.artistId ?? "nil"
        let durationForLog = String(format: "%.1f", durationListened)
        let trackDurationForLog = String(format: "%.1f", trackDuration)
        Logger.player.debug(
            "[STATS] Recorded: trigger=\(trigger, privacy: .public) trackId=\(song.id, privacy: .public) artistId=\(artistIdForLog, privacy: .public) durationListened=\(durationForLog, privacy: .public)s trackDuration=\(trackDurationForLog, privacy: .public)s startedAt=\(startDate, privacy: .public) completed=\(self.wasTrackCompletedNaturally, privacy: .public)"
        )
    }

    // MARK: - End of track

    func handleEndOfTrack() async {
        guard !isRestoringSession else {
            Logger.player.warning("[END-OF-TRACK] suppressed — session restore in progress")
            return
        }
        guard !isHandlingEndOfTrack else {
            Logger.player.warning("[END-OF-TRACK] already handling — skipping duplicate")
            return
        }
        isHandlingEndOfTrack = true
        defer { isHandlingEndOfTrack = false }
        let repeatMode = await MainActor.run { state.repeatMode }
        if repeatMode == .one {
            // Record this completed listen, then restart the same track.
            wasTrackCompletedNaturally = true
            await recordCurrentTrackPlayback(trigger: "repeat_one")
            wasTrackCompletedNaturally = false
            resetTrackAccumulator(isPlaying: true)
            if let source = currentSource {
                // Defensive: repeat-one was likely toggled on after fade-out had already started.
                // Stop any in-flight fade tasks and restore volume on the same audioPlayer before
                // restarting, so the looped track isn't silent. Inline cancel (not cancelFadeTasks)
                // to skip the redundant restore log path.
                fadeOutTask?.cancel(); fadeOutTask = nil
                fadeInTask?.cancel(); fadeInTask = nil
                isFadingOut = false
                audioPlayer.volume = restoredVolume
                audioPlayer.play(url: source.url, headers: source.customHeaders)
            }
        } else {
            // Signal natural completion — recordCurrentTrackPlayback() reads this in startPlayback().
            wasTrackCompletedNaturally = true
            do {
                try await skipToNext()
            } catch {
                Logger.player.error("[TRANSITION] handleEndOfTrack: skipToNext() failed: \(error, privacy: .public)")
            }
        }
    }

    /// The last track of the queue ended naturally with repeat off. Stop cleanly AT THE END — no wrap, and no
    /// muted "parking" play of track 1 (that muted play, plus its mute→pause race, was the phantom: a leaked
    /// audio fragment / RCC churn). The queue + current index/track are kept and the position is parked at the
    /// end; `stoppedAtEndOfQueue` makes `resume()` restart the queue from track 0 (option a).
    private func pauseAtEndOfQueue() async {
        // Record the last track's completion (it ended naturally), then reset the accumulators.
        await recordCurrentTrackPlayback(trigger: "end_of_queue")
        wasTrackCompletedNaturally = false
        accumulatedPlayedSeconds = 0
        currentPlaySegmentStart = nil
        trackPlayStartDate = nil

        cancelFadeTasks()
        stopProgressTimer()
        stopPositionSaveTimer()
        // The engine is at EOF — stop it (NO parking play) and release the session.
        audioPlayer.stop()
        #if os(iOS)
        sessionActivationRetryTask?.cancel()
        sessionActivationRetryTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        pendingRestoreInfo = nil
        stoppedAtEndOfQueue = true

        Logger.player.info("[PLAYBACK] End of queue (repeat off) — stopped cleanly at end; resume restarts from track 0")

        let duration = await MainActor.run { state.duration }
        await MainActor.run {
            state.playbackState = .paused
            state.position = duration   // park at the very end of the still-selected last track
        }
        await pushPositionSnapshot(rate: 0)
        await saveSession()

        let endTrack = await MainActor.run { state.currentTrack }
        if let ws = widgetSyncService {
            Task { [weak ws] in await ws?.onPlayStateChanged(isPlaying: false, currentSong: endTrack) }
        }
    }

    // MARK: - Delegate callbacks

    /// Called by AudioStreamingDelegate when AudioPlayer's state changes.
    func handleAudioStateChanged(_ newState: AudioPlayerState) async {
        switch newState {
        case .playing:
            guard let info = pendingRestoreInfo else { break }
            pendingRestoreInfo = nil
            // Seek while engine is running — processSource() is a no-op when paused.
            // Skip if stream is not seekable (Ogg Vorbis, live radio) or position is at start.
            if audioPlayer.isSeekable && info.seekTime > 1 {
                audioPlayer.seek(to: info.seekTime)
            }
            guard info.pause else {
                isRestoringSession = false
                break
            }
            // Give processSeekTime() 150 ms to clear the render buffer and reopen
            // the HTTP connection at the correct byte offset before pausing.
            // Stored so resume() can cancel the deferred pause via task.cancel().
            restorePauseTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                self.restorePauseTask = nil
                self.audioPlayer.pause()
                self.audioPlayer.volume = self.restoredVolume
                self.isMutedForRestore = false
                await MainActor.run { self.state.playbackState = .paused }
                self.stopProgressTimer()
                self.isRestoringSession = false
                Logger.player.info("[RESTORE] seek landed — paused at \(self.audioPlayer.progress, format: .fixed(precision: 1))s")
            }
        case .error:
            Logger.player.error("[PLAYER] AudioStreaming entered error state")
            let isLive = await MainActor.run { state.isLiveStream }
            if isLive {
                let name = await MainActor.run { state.currentRadio?.name ?? "" }
                await handleLiveStreamFailure(stationName: name, error: nil)
            } else {
                await MainActor.run { state.playbackState = .error(.timeout) }
            }
        default:
            break
        }
    }

    /// Called by AudioStreamingDelegate on unexpected errors.
    func handleAudioError(_ error: AudioPlayerError) async {
        Logger.player.error("[PLAYER] AudioStreaming unexpected error: \(error.localizedDescription, privacy: .public)")
        let isLive = await MainActor.run { state.isLiveStream }
        if isLive {
            let name = await MainActor.run { state.currentRadio?.name ?? "" }
            await handleLiveStreamFailure(stationName: name, error: nil)
        } else {
            await MainActor.run { state.playbackState = .error(.timeout) }
        }
    }

    // MARK: - Next track artwork pre-load

    private func preloadNextTrackArtwork() {
        Task {
            let (queue, currentIndex) = await MainActor.run { (state.queue, state.currentIndex) }
            let nextIndex = currentIndex + 1
            guard nextIndex < queue.count else { return }
            let nextTrack = queue[nextIndex]
            await artworkImageCache.load(coverArtId: nextTrack.coverArtId ?? nextTrack.id)
        }
    }

    // MARK: - Artwork / NowPlaying helpers

    private func resolveArtworkURL(for song: DisplayableSong) async -> URL? {
        guard let client = try? await serverService.makeSwiftSonicClient() else { return nil }
        let artId = song.coverArtId ?? song.id
        return client.coverArtURL(id: artId, size: 600)
    }

    // MARK: - Cache download helpers

    /// Downloads the track from its stream URL and stores it in AudioStreamCache.
    /// Uses URLSession.download for disk-streaming efficiency (temp file → read → store).
    private func downloadAndCache(
        songId: String,
        serverId: UUID,
        streamURL: URL,
        customHeaders: [String: String],
        using session: URLSession
    ) async throws {
        var request = URLRequest(url: streamURL)
        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (tempURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct CacheDownloadError: Error, Sendable { let statusCode: Int }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CacheDownloadError(statusCode: code)
        }

        // Never commit a poisoned payload (Subsonic error-as-200 envelope, empty or
        // truncated body) — a broken cache file plays as silence through FileAudioSource.
        try AudioResponseValidator.validate(fileAt: tempURL, response: response, songId: songId, logger: Logger.cache)

        let data = try Data(contentsOf: tempURL)
        let ext = streamURL.pathExtension
        let mimeType = response.mimeType ?? (ext.isEmpty ? "audio/mpeg" : "audio/\(ext)")

        _ = try await audioStreamCache.store(
            data: data,
            forSongId: songId,
            serverId: serverId,
            mimeType: mimeType
        )

        Logger.player.info("Cached '\(songId, privacy: .public)' from stream (\(data.count) bytes, \(mimeType, privacy: .public))")
    }

    // MARK: - NowPlaying position push

    /// Pushes a position-only snapshot when track metadata hasn't changed (pause/resume/seek).
    private func pushPositionSnapshot(rate: Float? = nil) async {
        let (track, position, playbackState, duration) = await MainActor.run {
            (state.currentTrack, state.position, state.playbackState, state.duration)
        }
        guard let track else { return }

        let resolvedRate: Float
        if let rate {
            resolvedRate = rate
        } else if case .playing = playbackState {
            resolvedRate = 1.0
        } else {
            resolvedRate = 0.0
        }

        let clampedPosition = duration > 0 ? min(position, duration) : position
        let snapshot = NowPlayingSnapshot(
            title: track.title,
            artist: track.artist,
            album: track.albumName,
            duration: duration,
            position: clampedPosition,
            playbackRate: resolvedRate,
            artworkURL: nil,
            artworkHeaders: [:],
            coverArtId: nil,
            isLiveStream: false,
            radioStationName: nil,
            songId: track.id
        )
        await nowPlayingService?.update(with: snapshot)
    }

    /// Called from the progress timer to keep MPNowPlayingInfoCenter in sync.
    /// Guards ensure we only push during live playback — not during transitions, live streams,
    /// or when elapsed is out of range — so we never send a stale or impossible position.
    private func periodicNowPlayingPush(elapsed: TimeInterval) async {
        let (playbackState, duration, isLiveStream, hasTrack) = await MainActor.run {
            (state.playbackState, state.duration, state.isLiveStream, state.currentTrack != nil)
        }
        guard case .playing = playbackState, !isLiveStream, hasTrack else { return }
        guard elapsed >= 0, duration > 0, elapsed <= duration else { return }
        await nowPlayingService?.pushPosition(elapsed: elapsed, rate: 1.0, duration: duration)
    }

    // nonisolated: safe — only called during app termination
    nonisolated func stopAudioEngineSync() {
        audioPlayer.stop()
    }
}

// MARK: - iOS Audio Session

#if os(iOS)
extension PlayerService {
    func configureAudioSessionIfNeeded() {
        do {
            let session = AVAudioSession.sharedInstance()
            if !audioSessionConfigured {
                // .playback disables the silent switch and allows background audio.
                // AirPlay + Bluetooth options enable wireless output without extra entitlements.
                try session.setCategory(.playback, options: [.allowAirPlay, .allowBluetoothHFP])
                audioSessionConfigured = true
            }
            // Always call setActive(true) — iOS may have deactivated the session during a
            // background interruption (phone call, Siri, other audio app) even after a
            // successful initial setup. Without this, resume() silently fails on the lock screen.
            try session.setActive(true)
        } catch let error as NSError {
            if error.code == -50 {
                // Code=-50: another app holds the session — retry after short delay.
                Logger.player.warning("AVAudioSession setActive Code=-50, retrying in 0.5s")
                sessionActivationRetryTask = Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled else { return }
                    try? AVAudioSession.sharedInstance().setActive(true)
                }
            } else {
                Logger.player.error("Failed to configure AVAudioSession: \(error, privacy: .public)")
            }
        }
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                Task { await self.handleAudioSessionInterruption(notification) }
            }
        }
        if routeChangeObserver == nil {
            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }
                // AVAudioSessionRouteDescription is not Sendable — extract the previous
                // route's port types here on the main queue before hopping to the actor.
                let previousOutputs = (notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
                    as? AVAudioSessionRouteDescription)?.outputs.map(\.portType) ?? []
                Task { await self.handleRouteChange(changeReason, previousOutputs: previousOutputs) }
            }
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) async {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Record route-disconnect interruptions (AirPods in case) before any early
            // return — .ended must never auto-resume those onto the built-in speaker.
            interruptionWasRouteDisconnect = (notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionReason.init(rawValue:)) == .routeDisconnected
            let isPlaying = await MainActor.run { state.playbackState == .playing }
            guard isPlaying else { return }
            // Cancel any active crossfade before the OS steals audio focus.
            cancelFadeTasks()
            audioPlayer.pause()
            await MainActor.run { state.playbackState = .paused }
            stopProgressTimer()
            await saveSession()
            let pauseTrack = await MainActor.run { state.currentTrack }
            if let ws = widgetSyncService {
                Task { [weak ws] in await ws?.onPlayStateChanged(isPlaying: false, currentSong: pauseTrack) }
            }
            Logger.player.info("[INTERRUPTION] began — paused playback")

        case .ended:
            let shouldResume = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .flatMap { AVAudioSession.InterruptionOptions(rawValue: $0) }
                .map { $0.contains(.shouldResume) } ?? false
            let wasRouteDisconnect = interruptionWasRouteDisconnect
            interruptionWasRouteDisconnect = false
            Logger.player.info("[INTERRUPTION] ended — shouldResume=\(shouldResume, privacy: .public) routeDisconnect=\(wasRouteDisconnect, privacy: .public)")
            if shouldResume && !wasRouteDisconnect {
                await resume()
            } else {
                Logger.player.info("[INTERRUPTION] ended — staying paused")
            }

        @unknown default:
            break
        }
    }

    // internal: accessible from tests via @testable import
    func handleRouteChange(
        _ reason: AVAudioSession.RouteChangeReason,
        previousOutputs: [AVAudioSession.Port] = []
    ) async {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            .map { $0.portType.rawValue }
            .joined(separator: ",")
        Logger.player.info("[ROUTE] routeChange reason=\(reason.logDescription, privacy: .public) outputs=[\(outputs, privacy: .public)]")

        switch reason {
        case .oldDeviceUnavailable:
            // Personal listening device went away (AirPods in case, headphones unplugged).
            // Do NOT gate on .playing — the routeDisconnected interruption (iOS 17+) may
            // already have flipped playbackState to .paused while the engine and session
            // are still primed to resume on the speaker. pause() is idempotent and also
            // deactivates the session, which is what actually prevents speaker playback.
            guard previousOutputs.isEmpty
                || PlayerService.isPersonalAudioRoute(portTypes: previousOutputs) else { break }
            let hasActiveTrack = await MainActor.run {
                state.currentTrack != nil && state.playbackState != .idle
            }
            if hasActiveTrack { await pause() }

        case .newDeviceAvailable, .routeConfigurationChange:
            try? AVAudioSession.sharedInstance().setActive(true)

        default:
            break
        }
    }
}
#endif

// MARK: - AudioStreamingDelegate

/// Bridges AudioPlayerDelegate callbacks (dispatched on main via asyncOnMain) to PlayerService (actor).
final class AudioStreamingDelegate: AudioPlayerDelegate, @unchecked Sendable {
    weak var service: PlayerService?

    func audioPlayerDidStartPlaying(player: AudioPlayer, with entryId: AudioEntryId) {}

    func audioPlayerDidFinishBuffering(player: AudioPlayer, with entryId: AudioEntryId) {}

    func audioPlayerStateChanged(
        player: AudioPlayer,
        with newState: AudioPlayerState,
        previous: AudioPlayerState
    ) {
        // [DIAG] Correlate with [NET-COVER] logs: underrun while cover fetches are in flight
        // confirms bandwidth starvation; underrun with no concurrent covers points elsewhere.
        if newState == .bufferring && previous == .playing {
            Logger.player.warning("[NET-AUDIO] buffer underrun — state: playing → bufferring")
        }
        guard let service else { return }
        Task { await service.handleAudioStateChanged(newState) }
    }

    func audioPlayerDidFinishPlaying(
        player: AudioPlayer,
        entryId: AudioEntryId,
        stopReason: AudioPlayerStopReason,
        progress: Double,
        duration: Double
    ) {
        // Only natural completions (eof) trigger end-of-track handling.
        // User-initiated play() or stop() arrive with .userAction / .none.
        guard let service, stopReason == .eof else { return }
        Task { await service.handleEndOfTrack() }
    }

    func audioPlayerUnexpectedError(player: AudioPlayer, error: AudioPlayerError) {
        guard let service else { return }
        Task { await service.handleAudioError(error) }
    }

    func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {}

    func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {}
}

// MARK: - iOS logging helpers (file-private)

#if os(iOS)
private extension AVAudioSession.RouteChangeReason {
    nonisolated var logDescription: String {
        switch self {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}
#endif
