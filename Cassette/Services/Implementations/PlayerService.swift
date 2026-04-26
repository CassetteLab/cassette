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
    private var nowPlayingService: (any NowPlayingServiceProtocol)?

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endOfTrackObserver: NSObjectProtocol?
    private var audioSessionConfigured = false
    private var positionSaveTask: Task<Void, Never>?
    // Saved before a shuffle activation; nil when shuffle is off.
    private var originalQueueOrder: [DisplayableSong]?

    init(
        state: PlayerState,
        mediaResolver: any MediaResolverProtocol,
        serverService: any ServerServiceProtocol,
        sessionService: PlaybackSessionService,
        artworkImageCache: ArtworkImageCache
    ) {
        self.state = state
        self.mediaResolver = mediaResolver
        self.serverService = serverService
        self.sessionService = sessionService
        self.artworkImageCache = artworkImageCache
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
            await MainActor.run { state.isShuffled = false }
        }

        guard let serverId = await MainActor.run(body: { serverService.state.activeServer?.id }) else {
            await MainActor.run { state.playbackState = .error(.serverNotConfigured) }
            throw CassetteError.serverNotConfigured
        }

        await MainActor.run {
            state.queue = tracks
            state.currentIndex = startIndex
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
        teardownPlayer()

        #if os(iOS)
        configureAudioSessionIfNeeded()
        #endif

        let item = makePlayerItem(source: source)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        setupEndOfTrackObserver(for: item)
        setupPeriodicTimeObserver(for: newPlayer)

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
            coverArtId: song.coverArtId
        )
        await nowPlayingService?.update(with: snapshot)
        await sessionService.save(playerState: state)
        startPositionSaveTimer()
        preloadNextTrackArtwork()
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
        teardownPlayer()
        await MainActor.run {
            state.playbackState = .idle
            state.currentTrack = nil
            state.queue = []
            state.position = 0
            state.duration = 0
        }
    }

    // MARK: - Seek

    func seek(to position: TimeInterval) async {
        let time = CMTime(seconds: position, preferredTimescale: 1000)
        await player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        await MainActor.run { state.position = position }
        await pushPositionSnapshot()
    }

    // MARK: - Skip

    func skipToNext() async throws {
        let (queue, currentIndex, repeatMode) = await MainActor.run {
            (state.queue, state.currentIndex, state.repeatMode)
        }
        let nextIndex = currentIndex + 1

        if nextIndex < queue.count {
            try await play(tracks: queue, startIndex: nextIndex)
        } else if repeatMode == .all {
            try await play(tracks: queue, startIndex: 0)
        } else {
            await stop()
        }
    }

    func skipToPrevious() async throws {
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
        await MainActor.run { state.repeatMode = mode }
        await sessionService.save(playerState: state)
    }

    func toggleShuffle() async {
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
        await MainActor.run { state.queue.append(contentsOf: tracks) }
        await sessionService.save(playerState: state)
    }

    func playNext(_ songs: [DisplayableSong]) async {
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
        await MainActor.run {
            guard state.queue.indices.contains(index) else { return }
            state.queue.remove(at: index)
        }
    }

    func moveInQueue(fromIndex: Int, toIndex: Int) async {
        await MainActor.run {
            guard state.queue.indices.contains(fromIndex),
                  state.queue.indices.contains(toIndex) else { return }
            let song = state.queue.remove(at: fromIndex)
            state.queue.insert(song, at: toIndex)
        }
    }

    // MARK: - Session persistence

    func restoreSession() async {
        guard let data = await sessionService.loadRestoredSession() else { return }

        let track = data.queue[data.currentIndex]
        await MainActor.run {
            state.queue = data.queue
            state.currentIndex = data.currentIndex
            state.currentTrack = track
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

        let cmTime = CMTime(seconds: position, preferredTimescale: 600)
        await newPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)

        await MainActor.run { state.isPlaybackAvailable = true }
        Logger.player.info("Session restore: '\(track.title)' prepared at \(position, format: .fixed(precision: 1))s")
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

    // MARK: - End of track

    private func handleEndOfTrack() async {
        let repeatMode = await MainActor.run { state.repeatMode }
        if repeatMode == .one {
            await seek(to: 0)
            player?.play()
        } else {
            try? await skipToNext()
        }
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

    private func setupEndOfTrackObserver(for item: AVPlayerItem) {
        endOfTrackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
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
            coverArtId: nil
        )
        await nowPlayingService?.update(with: snapshot)
    }
}
