// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
    private var nowPlayingService: (any NowPlayingServiceProtocol)?

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endOfTrackObserver: NSObjectProtocol?
    private var durationObserver: NSKeyValueObservation?
    private var audioSessionConfigured = false
    private var positionSaveTask: Task<Void, Never>?
    /// Task scheduling the `submission: true` scrobble at +30s after track start.
    /// Cancelled and replaced each time a new track starts via `startPlayback()`.
    private var scrobbleSubmissionTask: Task<Void, Never>?
    // Saved before a shuffle activation; nil when shuffle is off.
    private var originalQueueOrder: [DisplayableSong]?
    /// Single-slot guard preventing concurrent auto-extend fetches.
    private var autoExtendFetchTask: Task<Void, Never>?
    private nonisolated static let autoExtendUserDefaultsKey = "cassette.player.autoExtendEnabled"

    init(
        state: PlayerState,
        mediaResolver: any MediaResolverProtocol,
        serverService: any ServerServiceProtocol,
        sessionService: PlaybackSessionService,
        artworkImageCache: ArtworkImageCache,
        libraryService: any LibraryServiceProtocol
    ) {
        self.state = state
        self.mediaResolver = mediaResolver
        self.serverService = serverService
        self.sessionService = sessionService
        self.artworkImageCache = artworkImageCache
        self.libraryService = libraryService
    }

    /// Call from AppContainer after both PlayerService and NowPlayingService are created.
    func setNowPlayingService(_ service: any NowPlayingServiceProtocol) {
        nowPlayingService = service
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

        await startPlayback(song: song, source: source)
    }

    private func startPlayback(song: DisplayableSong, source: MediaSource) async {
        // Cancel any pending +30s scrobble from the previous track.
        cancelPendingScrobble()

        let songId = song.id
        Task { [libraryService] in
            await libraryService.scrobble(songId: songId, submission: false)
        }
        scrobbleSubmissionTask = Task { [libraryService] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await libraryService.scrobble(songId: songId, submission: true)
        }

        teardownPlayer()

        #if os(iOS)
        configureAudioSessionIfNeeded()
        #endif

        let item = makePlayerItem(source: source)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        setupEndOfTrackObserver(for: item)
        setupPeriodicTimeObserver(for: newPlayer)
        setupDurationObserver(for: item)
        startAssetDurationLoad(for: item, songId: song.id)

        newPlayer.play()

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
        let artworkHeaders = (try? await serverService.activeCredentials().customHeaders) ?? [:]
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
        await sessionService.save(playerState: state)
        startPositionSaveTimer()
        preloadNextTrackArtwork()
        await evaluateAutoExtend()
    }

    // MARK: - Live Stream

    func playRadio(_ station: InternetRadioStation) async throws {
        cancelPendingScrobble()
        let source = try await mediaResolver.resolveRadio(station)

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

        let item = makePlayerItem(source: source)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        // Duration and end-of-track observers are not attached — live streams have
        // indefinite duration and do not fire AVPlayerItemDidPlayToEndTime naturally.
        setupPeriodicTimeObserver(for: newPlayer)
        newPlayer.play()

        await MainActor.run {
            state.playbackState = .playing
            state.isPlaybackAvailable = true
        }

        let artworkHeaders = (try? await serverService.activeCredentials().customHeaders) ?? [:]
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
        player?.pause()
        await MainActor.run { state.playbackState = .paused }
        await pushPositionSnapshot(rate: 0.0)
        stopPositionSaveTimer()
        await sessionService.save(playerState: state)
    }

    func resume() async {
        #if os(iOS)
        configureAudioSessionIfNeeded()
        #endif
        player?.play()
        await MainActor.run { state.playbackState = .playing }
        await pushPositionSnapshot(rate: 1.0)
        startPositionSaveTimer()
    }

    // MARK: - Stop

    func stop() async {
        cancelPendingScrobble()
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
        await sessionService.save(playerState: state)
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
        await sessionService.save(playerState: state)
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
        await sessionService.save(playerState: state)
    }

    func playNext(_ songs: [DisplayableSong]) async {
        guard await MainActor.run(body: { !state.isLiveStream }) else {
            Logger.player.debug("playNext ignored — live stream mode")
            return
        }
        let (queue, currentIndex) = await MainActor.run { (state.queue, state.currentIndex) }
        if queue.isEmpty {
            try? await play(tracks: songs, startIndex: 0)
        } else {
            let insertAt = min(currentIndex + 1, queue.count)
            await MainActor.run { state.queue.insert(contentsOf: songs, at: insertAt) }
            Logger.player.info("Inserted \(songs.count) song(s) at queue position \(insertAt)")
            await sessionService.save(playerState: state)
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
        await sessionService.save(playerState: state)
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
        await sessionService.save(playerState: state)
    }

    // MARK: - Session persistence

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

        let item = makePlayerItem(source: source)
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
        let artworkHeaders = (try? await serverService.activeCredentials().customHeaders) ?? [:]
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

    // MARK: - End of track

    private func handleEndOfTrack() async {
        let repeatMode = await MainActor.run { state.repeatMode }
        if repeatMode == .one {
            await seek(to: 0)
            player?.play()
        } else {
            Logger.player.info("[TRANSITION] handleEndOfTrack: attempting skipToNext (errors swallowed)")
            try? await skipToNext()
        }
    }

    private func rewindToFirstTrackPaused() async {
        let queue = await MainActor.run { state.queue }
        guard let firstTrack = queue.first else {
            await stop()
            return
        }

        Logger.player.info("[PLAYBACK] End of queue — rewinding to first track paused")

        player?.pause()

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

        // Detach item-scoped observers from the expiring item
        if let observer = endOfTrackObserver {
            NotificationCenter.default.removeObserver(observer)
            endOfTrackObserver = nil
        }
        durationObserver?.invalidate()
        durationObserver = nil

        // Swap in new item without destroying the player or its time observer
        let newItem = makePlayerItem(source: source)
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
        await sessionService.save(playerState: state)
    }

    // MARK: - AVPlayer setup

    /// Builds an AVPlayerItem from a MediaSource.
    ///
    /// For `.stream`, custom headers are injected via the `"AVURLAssetHTTPHeaderFields"` key.
    /// This key exists in AVFoundation/AVURLAsset.h but is not publicly exported as a Swift
    /// constant — its raw string value is the stable interface (iOS 10+, confirmed in practice).
    /// It is the only way to inject per-request HTTP headers without an AVAssetResourceLoaderDelegate.
    /// ⚠ Monitor Apple AVFoundation release notes — Apple could remove or replace this mechanism.
    private func makePlayerItem(source: MediaSource) -> AVPlayerItem {
        let headers = source.customHeaders
        guard !headers.isEmpty else {
            return AVPlayerItem(url: source.url)
        }
        let asset = AVURLAsset(url: source.url, options: ["AVURLAssetHTTPHeaderFields": headers])
        return AVPlayerItem(asset: asset)
    }

    private func setupPeriodicTimeObserver(for player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        // .main queue so MainActor.assumeIsolated is valid in the block.
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.state.position = time.seconds
            }
        }
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
                await self?.updateDuration(newDuration)
            }
        }
    }

    private func updateDuration(_ newDuration: TimeInterval) async {
        let current = await MainActor.run { state.duration }
        guard abs(newDuration - current) > 0.1 else { return }
        Logger.player.info("[DURATION] \(current, format: .fixed(precision: 2))s → \(newDuration, format: .fixed(precision: 2))s (delta=\(abs(newDuration - current), format: .fixed(precision: 3))s)")
        await MainActor.run { state.duration = newDuration }
        await pushPositionSnapshot()
    }

    private func setupEndOfTrackObserver(for item: AVPlayerItem) {
        Logger.player.debug("[TRANSITION] setupEndOfTrackObserver: attaching observer for item \(item.debugDescription, privacy: .public)")
        endOfTrackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Logger.player.info("[TRANSITION] AVPlayerItemDidPlayToEndTime fired → handleEndOfTrack")
            Task { await self.handleEndOfTrack() }
        }
    }

    private func teardownPlayer() {
        stopPositionSaveTimer()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let observer = endOfTrackObserver {
            NotificationCenter.default.removeObserver(observer)
            endOfTrackObserver = nil
        }
        durationObserver?.invalidate()
        durationObserver = nil
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
        } catch {
            Logger.player.error("Failed to configure AVAudioSession: \(error, privacy: .public)")
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
        return client.coverArtURL(id: artId, size: 300)
    }

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
        let snapshot = NowPlayingSnapshot(
            title: track.title,
            artist: track.artist,
            album: track.albumName,
            duration: duration,
            position: position,
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
