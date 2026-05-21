// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import AVFoundation
import SwiftSonic
import OSLog

#if os(iOS)
import AVFAudio
#endif

actor PlayerService: PlayerServiceProtocol {
    nonisolated let state: PlayerState

    private let mediaResolver: any MediaResolverProtocol
    private let serverService: any ServerServiceProtocol
    private let sessionService: PlaybackSessionService
    private let artworkImageCache: ArtworkImageCache
    private let libraryService: any LibraryServiceProtocol
    private let cacheService: any CacheServiceProtocol
    private let downloadService: any DownloadServiceProtocol
    private let cacheSettings: CacheSettings
    private var nowPlayingService: (any NowPlayingServiceProtocol)?
    private var widgetSyncService: WidgetSyncService?
    private let toastService: ToastService
    private let statsService: StatsService

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endOfTrackObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var durationObserver: NSKeyValueObservation?
    private var liveStreamFailureObserver: NSKeyValueObservation?
    private var liveStreamStallTask: Task<Void, Never>?
    private var audioSessionConfigured = false
    #if os(iOS)
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    // AirPlay / route state
    private var isTransitioningTrack = false
    private var isPlayingIntent = false
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var stallRecoveryTask: Task<Void, Never>?
    #endif
    private var isHandlingEndOfTrack = false
    private var positionSaveTask: Task<Void, Never>?
    /// Task scheduling the `submission: true` scrobble at +30s after track start.
    /// Cancelled and replaced each time a new track starts via `startPlayback()`.
    private var scrobbleSubmissionTask: Task<Void, Never>?
    /// Task scheduled to download and cache the current track at +30s of playback.
    /// Cancelled when track changes via cancelPendingCacheDownload().
    private var cacheDownloadTask: Task<Void, Never>?
    private let cacheSession: URLSession
    // Saved before a shuffle activation; nil when shuffle is off.
    private var originalQueueOrder: [DisplayableSong]?
    /// Single-slot guard preventing concurrent auto-extend fetches.
    private var autoExtendFetchTask: Task<Void, Never>?
    private nonisolated static let autoExtendUserDefaultsKey = "cassette.player.autoExtendEnabled"

    /// Wall-clock time when the current track started playing. Nil before first track.
    private var trackStartDate: Date?
    /// Set to true by handleEndOfTrack before a natural completion transition; reset after recording.
    private var wasTrackCompletedNaturally: Bool = false

    init(
        state: PlayerState,
        mediaResolver: any MediaResolverProtocol,
        serverService: any ServerServiceProtocol,
        sessionService: PlaybackSessionService,
        artworkImageCache: ArtworkImageCache,
        libraryService: any LibraryServiceProtocol,
        cacheService: any CacheServiceProtocol,
        downloadService: any DownloadServiceProtocol,
        cacheSettings: CacheSettings,
        toastService: ToastService,
        statsService: StatsService
    ) {
        self.state = state
        self.mediaResolver = mediaResolver
        self.serverService = serverService
        self.sessionService = sessionService
        self.artworkImageCache = artworkImageCache
        self.libraryService = libraryService
        self.cacheService = cacheService
        self.downloadService = downloadService
        self.cacheSettings = cacheSettings
        self.toastService = toastService
        self.statsService = statsService
        let cacheConfig = URLSessionConfiguration.default
        cacheConfig.timeoutIntervalForRequest = 30
        cacheConfig.timeoutIntervalForResource = 30
        self.cacheSession = URLSession(configuration: cacheConfig)
    }

    /// Call from AppContainer after both PlayerService and NowPlayingService are created.
    func setNowPlayingService(_ service: any NowPlayingServiceProtocol) {
        nowPlayingService = service
    }

    func setWidgetSyncService(_ service: WidgetSyncService) {
        widgetSyncService = service
    }

    // MARK: - Play

    func play(tracks: [DisplayableSong], startIndex: Int) async throws {
        guard tracks.indices.contains(startIndex) else { return }

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
        await recordCurrentTrackPlayback()
        wasTrackCompletedNaturally = false
        trackStartDate = Date()

        // Cancel any pending +30s scrobble and cache download from the previous track.
        cancelPendingScrobble()
        cancelPendingCacheDownload()

        let songId = song.id
        Task { [libraryService] in
            await libraryService.scrobble(songId: songId, submission: false)
        }
        scrobbleSubmissionTask = Task { [libraryService] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await libraryService.scrobble(songId: songId, submission: true)
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
                cacheDownloadTask = Task { [cacheService, downloadService, serverService, weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    if await cacheService.cachedURL(forSongId: songId, serverId: serverId) != nil { return }
                    if await downloadService.isDownloaded(songId: songId, serverId: serverId) { return }
                    let isExpensive = await MainActor.run { serverService.state.isExpensive }
                    if isExpensive && !allowCellular {
                        Logger.player.debug("Cache skipped — cellular for '\(songId, privacy: .public)'")
                        return
                    }
                    do {
                        try await self?.downloadAndCache(
                            songId: songId,
                            serverId: serverId,
                            streamURL: cacheStreamURL,
                            customHeaders: customHeaders
                        )
                    } catch {
                        Logger.player.debug("Cache download failed for '\(songId, privacy: .public)': \(error, privacy: .public)")
                    }
                }
            } else {
                Logger.player.debug("Cache: no URL for '\(songId, privacy: .public)' in \(cacheFormat.rawValue) — skipping")
            }
        }

        Logger.player.info("[TRANSITION] advancing to '\(song.title, privacy: .public)' (id=\(song.id, privacy: .public)) — teardown begin")
        #if os(iOS)
        isTransitioningTrack = true
        #endif
        teardownPlayer()

        #if os(iOS)
        configureAudioSessionIfNeeded()
        #endif

        #if DEBUG
        if case .stream(let streamURL, let customHeaders) = source {
            var curlCmd = "curl -I \"\(streamURL.absoluteString)\""
            for (key, value) in customHeaders.sorted(by: { $0.key < $1.key }) {
                curlCmd += " \\\n  -H \"\(key): \(value)\""
            }
            print("[DEBUG-CURL] \(curlCmd)")
        }
        #endif

        let item = await makePlayerItem(source: source, expectedDuration: song.duration)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        setupEndOfTrackObserver(for: item)
        setupPeriodicTimeObserver(for: newPlayer)
        setupDurationObserver(for: item)
        startAssetDurationLoad(for: item, songId: song.id)

        newPlayer.play()
        Logger.player.info("[TRANSITION] new player started for '\(song.title, privacy: .public)' — awaiting timeControlStatus=.playing confirmation")
        #if os(iOS)
        isPlayingIntent = true
        setupTimeControlStatusObserver(for: newPlayer)
        #endif

        let duration = song.duration
        await MainActor.run {
            state.currentTrack = song
            state.duration = duration
            state.position = 0
            state.playbackState = .playing
            state.isPlaybackAvailable = true
        }

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
            radioStationName: nil
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

        #if os(iOS)
        isTransitioningTrack = true
        #endif
        teardownPlayer()

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

        let item = await makePlayerItem(source: source)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        // Duration and end-of-track observers are not attached — live streams have
        // indefinite duration and do not fire AVPlayerItemDidPlayToEndTime naturally.
        setupPeriodicTimeObserver(for: newPlayer)
        newPlayer.play()
        setupLiveStreamObservers(for: item, stationName: station.name)

        await MainActor.run {
            state.playbackState = .playing
            state.isPlaybackAvailable = true
        }
        #if os(iOS)
        // Live streams use liveStreamStallTask for stall detection; no timeControlStatus observer.
        isPlayingIntent = true
        isTransitioningTrack = false
        #endif

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
            radioStationName: station.name
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
            Logger.player.debug("[RADIO-CODEC] HEAD request failed or timed out — letting AVPlayer try")
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
        Logger.player.debug("[RADIO-CODEC] content-type=\(contentType.isEmpty ? "(empty)" : contentType, privacy: .public) → ambiguous, letting AVPlayer try")
        return .ambiguous
    }

    private func setupLiveStreamObservers(for item: AVPlayerItem, stationName: String) {
        // Immediate failure: AVPlayerItem.status transitions to .failed
        liveStreamFailureObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }
            let error = observedItem.error
            Task { [weak self] in
                await self?.handleLiveStreamFailure(stationName: stationName, error: error)
            }
        }

        // Stall detection: if state.position (driven by the periodic time observer) hasn't
        // advanced past 1s after 8s of attempted playback, the stream is stalled or undecodable.
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

        teardownPlayer()

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

    func setVolume(_ volume: Float) async {
        let clamped = max(0, min(1, volume))
        player?.volume = clamped
        UserDefaults.standard.set(clamped, forKey: "cassette.lastVolume")
    }

    func setAutoExtendEnabled(_ enabled: Bool) async {
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

    /// Reads queue position and fires a background fetch + append when ≤15 tracks remain.
    /// Called at the end of every startPlayback(). Guarded by a single-slot task to prevent
    /// parallel fetches when tracks advance rapidly. Errors are swallowed — natural queue
    /// end is the graceful fallback.
    private func evaluateAutoExtend() async {
        let (isEnabled, repeatMode, currentRadio, remaining) = await MainActor.run {
            let remaining = state.queue.count - state.currentIndex - 1
            return (state.isAutoExtendEnabled, state.repeatMode, state.currentRadio, remaining)
        }
        guard isEnabled else { return }
        guard repeatMode == .off else { return }
        guard currentRadio == nil else { return }
        guard autoExtendFetchTask == nil else { return }
        // Trigger threshold : 15 or fewer tracks remaining (including zero — covers singles
        // and starting from the last track of an album).
        guard remaining <= 15 else { return }

        Logger.player.info("Auto-extend triggered: \(remaining) tracks remaining, fetching 50 more")

        autoExtendFetchTask = Task { [libraryService, weak self] in
            defer { Task { await self?.clearAutoExtendFetchTask() } }
            do {
                let tracks = try await libraryService.smartShuffleQueue(targetSize: 50)
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

    /// Removes auto-extended tracks when the user is still in the original zone.
    /// If the user has already advanced into the extended zone, the queue is left intact.
    private func truncateExtensions() async {
        let (boundary, currentIndex, queueCount) = await MainActor.run {
            (state.originalQueueEndIndex, state.currentIndex, state.queue.count)
        }
        guard let boundary else { return }
        guard currentIndex < boundary else { return }
        guard boundary < queueCount else { return }
        await MainActor.run {
            state.queue = Array(state.queue[0..<boundary])
            state.originalQueueEndIndex = nil
        }
        Logger.player.info("Auto-extend tail truncated at boundary \(boundary) (currentIndex=\(currentIndex))")
    }

    // MARK: - Pause / Resume

    func pause() async {
        #if os(iOS)
        isPlayingIntent = false
        #endif
        player?.pause()
        await MainActor.run { state.playbackState = .paused }
        await pushPositionSnapshot(rate: 0.0)
        stopPositionSaveTimer()
        await saveSession()
        let pauseTrack = await MainActor.run { state.currentTrack }
        if let ws = widgetSyncService {
            Task { [weak ws] in await ws?.onPlayStateChanged(isPlaying: false, currentSong: pauseTrack) }
        }
    }

    func resume() async {
        #if os(iOS)
        configureAudioSessionIfNeeded()
        isPlayingIntent = true
        #endif
        // Lazily set trackStartDate for session-restored tracks that resume for the first time.
        if trackStartDate == nil {
            trackStartDate = Date()
        }
        player?.play()
        await MainActor.run { state.playbackState = .playing }
        await pushPositionSnapshot(rate: 1.0)
        startPositionSaveTimer()
        let resumeTrack = await MainActor.run { state.currentTrack }
        if let ws = widgetSyncService {
            Task { [weak ws] in await ws?.onPlayStateChanged(isPlaying: true, currentSong: resumeTrack) }
        }
    }

    func togglePlayPause() async {
        let isPlaying = await MainActor.run { state.playbackState == .playing }
        if isPlaying { await pause() } else { await resume() }
    }

    // MARK: - Stop

    func stop() async {
        #if os(iOS)
        isPlayingIntent = false
        #endif
        cancelPendingScrobble()
        cancelPendingCacheDownload()
        teardownPlayer()
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
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("seek ignored — live stream mode")
            return
        }
        let time = CMTime(seconds: position, preferredTimescale: 1000)
        await player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
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
            await rewindToFirstTrackPaused()
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
        }
    }

    func playNext(_ song: DisplayableSong) async {
        await playNext([song])
    }

    func addToQueue(_ songs: [DisplayableSong]) async {
        await appendToQueue(songs)
    }

    func addToQueue(_ song: DisplayableSong) async {
        await appendToQueue([song])
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

        await prepareCurrentTrackForRestoration(track: track, position: data.currentPosition)
        let savedVolume = Float(UserDefaults.standard.double(forKey: "cassette.lastVolume"))
        if savedVolume > 0 { player?.volume = savedVolume }
        Logger.player.info("Session restored: \(data.queue.count) tracks, index \(data.currentIndex), pos=\(data.currentPosition, format: .fixed(precision: 1))s")
    }

    private func prepareCurrentTrackForRestoration(track: DisplayableSong, position: TimeInterval) async {
        guard let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) else {
            Logger.player.warning("Session restore: no active server, skipping AVPlayer prep")
            return
        }

        let source: MediaSource
        do {
            source = try await mediaResolver.resolve(songId: track.id, serverId: serverId)
        } catch {
            Logger.player.error("Session restore: failed to resolve media — \(error)")
            await MainActor.run { state.isPlaybackAvailable = false }
            return
        }

        teardownPlayer()
        #if os(iOS)
        configureAudioSessionIfNeeded()
        #endif

        let item = await makePlayerItem(source: source, expectedDuration: track.duration)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        setupEndOfTrackObserver(for: item)
        setupPeriodicTimeObserver(for: newPlayer)
        setupDurationObserver(for: item)

        let cmTime = CMTime(seconds: position, preferredTimescale: 600)
        await newPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)

        await MainActor.run { state.isPlaybackAvailable = true }
        Logger.player.info("Session restore: '\(track.title)' prepared at \(position, format: .fixed(precision: 1))s")

        // Populate MPNowPlayingInfoCenter in paused state so lock screen controls
        // appear immediately when the user resumes — resume() only sends a
        // position-only update which would start from an empty dict otherwise.
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
            radioStationName: nil
        ))
    }

    func handleNetworkRestored() async {
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
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                let position = await MainActor.run { state.position }
                await sessionService.savePosition(position)
            }
        }
    }

    private func stopPositionSaveTimer() {
        positionSaveTask?.cancel()
        positionSaveTask = nil
    }

    // MARK: - Scrobble

    /// Cancels any pending `submission: true` scrobble. Called when switching tracks,
    /// switching to radio, or stopping. Safe to call when no task is scheduled.
    private func cancelPendingScrobble() {
        scrobbleSubmissionTask?.cancel()
        scrobbleSubmissionTask = nil
    }

    private func cancelPendingCacheDownload() {
        cacheDownloadTask?.cancel()
        cacheDownloadTask = nil
    }

    // MARK: - Stats recording

    private func recordCurrentTrackPlayback() async {
        guard let song = await MainActor.run(body: { state.currentTrack }),
              let startDate = trackStartDate else { return }
        guard let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) else { return }

        let durationListened = Date().timeIntervalSince(startDate)
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
        await statsService.recordPlayback(dto)
        Logger.player.debug("[STATS] Recorded playback: trackId=\(song.id, privacy: .public) duration=\(durationListened, format: .fixed(precision: 1))s completed=\(self.wasTrackCompletedNaturally, privacy: .public)")
    }

    // MARK: - End of track

    private func handleEndOfTrack() async {
        #if os(iOS)
        guard !isTransitioningTrack else {
            Logger.player.warning("[END-OF-TRACK] fired during transition — skipping")
            return
        }
        #endif
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
            await recordCurrentTrackPlayback()
            wasTrackCompletedNaturally = false
            trackStartDate = Date()
            // Re-attach the observer so AVPlayerItemDidPlayToEndTime fires on the next
            // iteration. The same AVPlayerItem is reused; explicit teardown+setup guards
            // against any platform edge case where the notification silently stops firing.
            if let item = player?.currentItem {
                if let old = endOfTrackObserver { NotificationCenter.default.removeObserver(old) }
                setupEndOfTrackObserver(for: item)
            }
            await seek(to: 0)
            player?.play()
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

    private func rewindToFirstTrackPaused() async {
        // Last track of the queue ended naturally — record it before rewinding.
        await recordCurrentTrackPlayback()
        wasTrackCompletedNaturally = false
        trackStartDate = nil

        let queue = await MainActor.run { state.queue }
        guard let firstTrack = queue.first else {
            await stop()
            return
        }

        Logger.player.info("[PLAYBACK] End of queue — rewinding to first track paused")

        player?.pause()
        #if os(iOS)
        isPlayingIntent = false
        #endif

        guard let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) else {
            await stop()
            return
        }

        let source: MediaSource
        do {
            source = try await mediaResolver.resolve(songId: firstTrack.id, serverId: serverId)
        } catch {
            Logger.player.error("[PLAYBACK] rewindToFirstTrackPaused: media resolve failed — \(error)")
            await stop()
            return
        }

        // Swap in new item without destroying the player or its time observer
        teardownCurrentItem()
        let newItem = await makePlayerItem(source: source, expectedDuration: firstTrack.duration)
        player?.replaceCurrentItem(with: newItem)

        setupEndOfTrackObserver(for: newItem)
        setupDurationObserver(for: newItem)
        startAssetDurationLoad(for: newItem, songId: firstTrack.id)

        await player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)

        let duration = firstTrack.duration
        await MainActor.run {
            state.currentIndex = 0
            state.currentTrack = firstTrack
            state.position = 0
            state.duration = duration
            state.playbackState = .paused
        }

        stopPositionSaveTimer()
        await pushPositionSnapshot(rate: 0)
        await saveSession()
    }

    // MARK: - AVPlayer setup

    /// Builds an AVPlayerItem from a MediaSource.
    ///
    /// For `.stream`, custom headers are injected via the `"AVURLAssetHTTPHeaderFields"` key.
    /// Private AVFoundation key (iOS 10+, stable in practice). No public Swift constant exists.
    /// Monitor AVFoundation release notes.
    /// Fallback if removed: AVAssetResourceLoaderDelegate (planned v1.x).
    private func makePlayerItem(source: MediaSource, expectedDuration: TimeInterval? = nil) async -> AVPlayerItem {
        let headers = source.customHeaders
        let item: AVPlayerItem
        if case .stream(let url, _) = source {
            // Preload asset properties before creating AVPlayerItem so AVFoundation resolves
            // the real FLAC duration from STREAMINFO before playback starts. Without this,
            // forwardPlaybackEndTime is set against an unresolved duration and tracks cut off early.
            let asset: AVURLAsset
            if headers.isEmpty {
                asset = AVURLAsset(url: url)
            } else {
                asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFields": headers])
            }
            do {
                async let duration = asset.load(.duration)
                async let tracks = asset.load(.tracks)
                async let isPlayable = asset.load(.isPlayable)
                _ = try await (duration, tracks, isPlayable)
                Logger.player.debug("[PRELOAD] Asset preloaded for stream — real duration resolved before playback")
            } catch {
                Logger.player.warning("[PRELOAD] Asset preload failed for stream, proceeding without: \(error, privacy: .public)")
            }
            item = AVPlayerItem(asset: asset)
        } else if headers.isEmpty {
            item = AVPlayerItem(url: source.url)
        } else {
            let asset = AVURLAsset(url: source.url, options: ["AVURLAssetHTTPHeaderFields": headers])
            item = AVPlayerItem(asset: asset)
        }
        if source.isLiveStream {
            // Default buffer is too conservative for high-bitrate FLAC streams; 15s absorbs cellular/wifi jitter.
            item.preferredForwardBufferDuration = 15.0
        }
        // Bound the playback timeline to the known audio duration. Tagged FLAC files contain a
        // MJPEG video stream (embedded cover art / attached_pic). Without this bound, AVPlayer
        // waits for that visual stream to exhaust its timeline before firing
        // AVPlayerItemDidPlayToEndTime, causing currentTime to drift 6–13 s past audio duration.
        if !source.isLiveStream, let duration = expectedDuration, duration > 0 {
            item.forwardPlaybackEndTime = CMTime(seconds: duration, preferredTimescale: 1000)
        }
        return item
    }

    private func setupPeriodicTimeObserver(for player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        // .main queue so MainActor.assumeIsolated is valid in the block.
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let current = time.seconds
            MainActor.assumeIsolated {
                let dur = self.state.duration
                self.state.position = dur > 0 ? min(current, dur) : current
            }
            Task { [weak self] in await self?.periodicNowPlayingPush(elapsed: current) }
        }
    }

    /// Called from the periodic time observer to keep MPNowPlayingInfoCenter in sync.
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

    // Loads the real asset duration asynchronously via full file parsing.
    // AVPlayerItem.duration (from the header) can underestimate the true length on
    // some transcoded files. This runs concurrently with playback and refines
    // state.duration when the result meaningfully differs from the header estimate.
    private func startAssetDurationLoad(for item: AVPlayerItem, songId: String) {
        Task { [weak self] in
            guard let self else { return }
            let asset = await MainActor.run { item.asset }
            Logger.player.debug("[DURATION] asset.load starting for songId=\(songId, privacy: .public)")
            do {
                let cmDuration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(cmDuration)
                Logger.player.debug("[DURATION] asset.load result: \(seconds, format: .fixed(precision: 4))s (CMTime flags=\(cmDuration.flags.rawValue))")
                guard seconds.isFinite, !seconds.isNaN, seconds > 0 else {
                    Logger.player.warning("[DURATION] Asset load returned invalid: \(seconds)")
                    return
                }
                let (currentTrackId, currentDuration) = await MainActor.run {
                    (self.state.currentTrack?.id, self.state.duration)
                }
                guard currentTrackId == songId else {
                    Logger.player.debug("[DURATION] Track changed during asset load, discarding")
                    return
                }
                // Always refine forwardPlaybackEndTime to the true asset duration, even when
                // the delta is too small to justify a state.duration update. This keeps the
                // end-of-track boundary accurate regardless of the Subsonic metadata precision.
                await self.updateForwardPlaybackEndTime(to: max(seconds, currentDuration), for: item)
                guard abs(seconds - currentDuration) > 0.5 else {
                    Logger.player.debug("[DURATION] asset.load matches header (delta<0.5s): asset=\(seconds, format: .fixed(precision: 4))s state=\(currentDuration, format: .fixed(precision: 4))s")
                    return
                }
                Logger.player.info("[DURATION] Refined via asset.load: \(currentDuration, format: .fixed(precision: 2))s → \(seconds, format: .fixed(precision: 2))s (delta=\(abs(seconds - currentDuration), format: .fixed(precision: 3))s)")
                await MainActor.run { self.state.duration = seconds }
                await self.pushPositionSnapshot()
            } catch {
                Logger.player.error("[DURATION] Asset load failed: \(error, privacy: .public)")
            }
        }
    }

    private func setupDurationObserver(for item: AVPlayerItem) {
        durationObserver?.invalidate()
        // .initial fires immediately with whatever AVPlayer knows now; .new fires on each update.
        // AVPlayer refines AVPlayerItem.duration multiple times as it parses the asset header.
        durationObserver = item.observe(\.duration, options: [.new, .initial]) { [weak self] observedItem, _ in
            let newDuration = observedItem.duration.seconds
            guard newDuration.isFinite, !newDuration.isNaN, newDuration > 0 else { return }
            Task { [weak self] in
                await self?.updateDuration(newDuration, for: observedItem)
            }
        }
    }

    private func updateDuration(_ newDuration: TimeInterval, for item: AVPlayerItem) async {
        let current = await MainActor.run { state.duration }
        guard abs(newDuration - current) > 0.1 else { return }
        Logger.player.info("[DURATION] \(current, format: .fixed(precision: 2))s → \(newDuration, format: .fixed(precision: 2))s (delta=\(abs(newDuration - current), format: .fixed(precision: 3))s)")
        await MainActor.run { state.duration = newDuration }
        updateForwardPlaybackEndTime(to: newDuration, for: item)
        await pushPositionSnapshot()
    }

    private func updateForwardPlaybackEndTime(to seconds: TimeInterval, for item: AVPlayerItem) {
        guard item.forwardPlaybackEndTime.isValid else { return }
        item.forwardPlaybackEndTime = CMTime(seconds: seconds, preferredTimescale: 1000)
    }

    private func setupEndOfTrackObserver(for item: AVPlayerItem) {
        Logger.player.debug("[TRANSITION] setupEndOfTrackObserver: attaching observers for item \(item.debugDescription, privacy: .public)")
        endOfTrackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Logger.player.info("[TRANSITION] AVPlayerItemDidPlayToEndTime fired → handleEndOfTrack")
            Task { [weak self] in await self?.handleEndOfTrack() }
        }
        if let old = failedToEndObserver {
            NotificationCenter.default.removeObserver(old)
        }
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Logger.player.error("[TRANSITION] AVPlayerItemFailedToPlayToEndTime: \(error?.localizedDescription ?? "nil", privacy: .public)")
        }
    }

    /// Removes item-scoped observers only. Safe to call before replaceCurrentItem(with:).
    /// Does NOT touch the player instance, timeObserverToken, or session observers.
    private func teardownCurrentItem() {
        if let observer = endOfTrackObserver {
            NotificationCenter.default.removeObserver(observer)
            endOfTrackObserver = nil
        }
        if let observer = failedToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            failedToEndObserver = nil
        }
        durationObserver?.invalidate()
        durationObserver = nil
        liveStreamFailureObserver?.invalidate()
        liveStreamFailureObserver = nil
        liveStreamStallTask?.cancel()
        liveStreamStallTask = nil
        #if os(iOS)
        stallRecoveryTask?.cancel()
        stallRecoveryTask = nil
        #endif
    }

    private func teardownPlayer() {
        stopPositionSaveTimer()
        teardownCurrentItem()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        #if os(iOS)
        // timeControlStatusObserver and stallRecoveryTask are player-scoped.
        // isTransitioningTrack is NOT reset here — startPlayback() sets it true before calling
        // teardownPlayer() and relies on it persisting through the synchronous teardown sequence.
        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        #endif
        player?.pause()
        player = nil
    }

    #if os(iOS)
    private func configureAudioSessionIfNeeded() {
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
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
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
                Task { await self.handleRouteChange(changeReason) }
            }
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) async {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            let isPlaying = await MainActor.run { state.playbackState == .playing }
            guard isPlaying else { return }
            await MainActor.run { state.playbackState = .paused }
            stopPositionSaveTimer()
            await saveSession()
            let pauseTrack = await MainActor.run { state.currentTrack }
            if let ws = widgetSyncService {
                Task { [weak ws] in await ws?.onPlayStateChanged(isPlaying: false, currentSong: pauseTrack) }
            }
            Logger.player.info("[INTERRUPTION] began — intent=\(self.isPlayingIntent, privacy: .public) timeControlStatus=\(self.player?.timeControlStatus.logDescription ?? "nil", privacy: .public)")

        case .ended:
            let shouldResume = notification.userInfo?[AVAudioSessionInterruptionOptionKey]
                .flatMap { AVAudioSession.InterruptionOptions(rawValue: $0 as! UInt) }
                .map { $0.contains(.shouldResume) } ?? false
            Logger.player.info("[INTERRUPTION] ended — shouldResume=\(shouldResume, privacy: .public) intent=\(self.isPlayingIntent, privacy: .public)")
            if shouldResume {
                await resume()
            } else {
                Logger.player.info("[INTERRUPTION] ended — shouldResume false, staying paused")
            }

        @unknown default:
            break
        }
    }

    // MARK: - Route & timeControlStatus handling (H1 / H2 / H3)

    private func setupTimeControlStatusObserver(for player: AVPlayer) {
        timeControlStatusObserver?.invalidate()
        stallRecoveryTask?.cancel()
        stallRecoveryTask = nil
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
            let status = observedPlayer.timeControlStatus
            let reason = observedPlayer.reasonForWaitingToPlay?.rawValue
            Task { [weak self] in await self?.handleTimeControlStatus(status, waitingReason: reason) }
        }
    }

    // internal: accessible from tests via @testable import
    func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus, waitingReason: String?) async {
        Logger.player.info("[ROUTE] timeControlStatus=\(status.logDescription, privacy: .public) reason=\(waitingReason ?? "nil", privacy: .public) isTransitioning=\(self.isTransitioningTrack, privacy: .public) intent=\(self.isPlayingIntent, privacy: .public)")
        switch status {
        case .playing:
            if isTransitioningTrack {
                Logger.player.info("[TRANSITION] playback confirmed on new player — clearing isTransitioningTrack")
            }
            isTransitioningTrack = false
            stallRecoveryTask?.cancel()
            stallRecoveryTask = nil

        case .waitingToPlayAtSpecifiedRate:
            guard isPlayingIntent, stallRecoveryTask == nil else { return }
            stallRecoveryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await self?.recoverFromStall()
            }

        case .paused:
            stallRecoveryTask?.cancel()
            stallRecoveryTask = nil

        @unknown default:
            break
        }
    }

    private func recoverFromStall() async {
        // Clear the transition guard regardless — 3 s is long enough; a real disconnect
        // after this point is a genuine user-facing event, not a teardown artefact.
        isTransitioningTrack = false
        guard isPlayingIntent else {
            Logger.player.debug("[ROUTE] Stall recovery cancelled — intent is paused")
            return
        }
        guard let p = player, p.timeControlStatus == .waitingToPlayAtSpecifiedRate else {
            Logger.player.debug("[ROUTE] Stall recovery: player no longer stalled, skipping")
            return
        }
        Logger.player.warning("[ROUTE] Stall recovery: calling play() after 3 s in waitingToPlayAtSpecifiedRate")
        p.play()
        stallRecoveryTask = nil
    }

    // internal: accessible from tests via @testable import
    func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason) async {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            .map { $0.portType.rawValue }
            .joined(separator: ",")
        Logger.player.info("[ROUTE] routeChange reason=\(reason.logDescription, privacy: .public) outputs=[\(outputs, privacy: .public)] isTransitioning=\(self.isTransitioningTrack, privacy: .public) intent=\(self.isPlayingIntent, privacy: .public) timeControlStatus=\(self.player?.timeControlStatus.logDescription ?? "nil", privacy: .public)")

        switch reason {
        case .oldDeviceUnavailable:
            guard !isTransitioningTrack else {
                // Spurious .oldDeviceUnavailable caused by AVPlayer teardown during track
                // transition — the new player is already starting; do not pause it.
                Logger.player.info("[ROUTE] .oldDeviceUnavailable suppressed — track transition in progress")
                return
            }
            await pause()

        case .newDeviceAvailable, .routeConfigurationChange:
            try? AVAudioSession.sharedInstance().setActive(true)
            // H3: if the player went to .paused during route reconfiguration but intent says
            // we should be playing, explicitly re-trigger play() (Apple recommendation).
            if isPlayingIntent, let p = player, p.timeControlStatus == .paused {
                Logger.player.info("[ROUTE] \(reason.logDescription, privacy: .public) — re-triggering play() (intent=playing, timeControlStatus=paused)")
                p.play()
            }

        default:
            break
        }
    }
    #endif

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

    /// Downloads the track from its stream URL and stores it in CacheService.
    /// Uses URLSession.download for disk-streaming efficiency (temp file → read → store).
    private func downloadAndCache(
        songId: String,
        serverId: UUID,
        streamURL: URL,
        customHeaders: [String: String]
    ) async throws {
        var request = URLRequest(url: streamURL)
        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (tempURL, response) = try await cacheSession.download(for: request)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct CacheDownloadError: Error, Sendable { let statusCode: Int }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CacheDownloadError(statusCode: code)
        }

        let data = try Data(contentsOf: tempURL)
        let ext = streamURL.pathExtension
        let mimeType = response.mimeType ?? (ext.isEmpty ? "audio/mpeg" : "audio/\(ext)")

        _ = try await cacheService.store(
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
            radioStationName: nil
        )
        await nowPlayingService?.update(with: snapshot)
    }
}

// MARK: - Test helpers (DEBUG + iOS only)

#if os(iOS) && DEBUG
extension PlayerService {
    func setTestTransitioningTrack(_ value: Bool) { isTransitioningTrack = value }
    func setTestPlayingIntent(_ value: Bool) { isPlayingIntent = value }
    var testIsTransitioningTrack: Bool { isTransitioningTrack }
    var testIsPlayingIntent: Bool { isPlayingIntent }
    var testHasStallRecoveryTask: Bool { stallRecoveryTask != nil }
}
#endif

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

private extension AVPlayer.TimeControlStatus {
    nonisolated var logDescription: String {
        switch self {
        case .paused: return "paused"
        case .playing: return "playing"
        case .waitingToPlayAtSpecifiedRate: return "waitingToPlayAtSpecifiedRate"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}
#endif
