// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import MediaPlayer
import OSLog

/// Manages MPNowPlayingInfoCenter + MPRemoteCommandCenter.
/// Active from v1 (lockscreen, Control Center, AirPods, Apple Watch).
/// Architected as the direct extension point for CarPlay (v1.2) — no refactor needed.
actor NowPlayingService: NowPlayingServiceProtocol {
    private let playerService: any PlayerServiceProtocol
    private let artworkLoader = ArtworkLoader()
    private let artworkImageCache: ArtworkImageCache
    private var commandsRegistered = false

    init(playerService: any PlayerServiceProtocol, artworkImageCache: ArtworkImageCache) {
        self.playerService = playerService
        self.artworkImageCache = artworkImageCache
    }

    // MARK: - Lifecycle

    func start() async {
        guard !commandsRegistered else { return }
        commandsRegistered = true

        let center = MPRemoteCommandCenter.shared()
        let playerService = playerService

        center.playCommand.addTarget { [playerService] _ in
            Task.detached(priority: .userInitiated) {
                await playerService.resume()
            }
            return .success
        }

        center.pauseCommand.addTarget { [playerService] _ in
            Task.detached(priority: .userInitiated) {
                await playerService.pause()
            }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [playerService] _ in
            Task.detached(priority: .userInitiated) {
                await playerService.togglePlayPause()
            }
            return .success
        }

        center.nextTrackCommand.addTarget { [playerService] _ in
            Task.detached(priority: .userInitiated) {
                do {
                    try await playerService.skipToNext()
                } catch {
                    Logger.nowPlaying.error("[PLAYBACK] skipToNext failed: \(error, privacy: .public)")
                }
            }
            return .success
        }
        appendToDebugLog("[RCC] start() — registered nextTrackCommand")

        center.previousTrackCommand.addTarget { [playerService] _ in
            Task.detached(priority: .userInitiated) {
                do {
                    try await playerService.skipToPrevious()
                } catch {
                    Logger.nowPlaying.error("[PLAYBACK] skipToPrevious failed: \(error, privacy: .public)")
                }
            }
            return .success
        }
        appendToDebugLog("[RCC] start() — registered previousTrackCommand")

        #if os(macOS)
        // macOS Control Center may route the previous-track gesture through skipBackwardCommand
        // instead of previousTrackCommand. Register both so the gesture works on either path.
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 0)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { try? await self.playerService.skipToPrevious() }
            return .success
        }
        #endif

        center.changePlaybackPositionCommand.addTarget { [playerService] event in
            guard let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = seekEvent.positionTime
            Task.detached(priority: .userInitiated) {
                await playerService.seek(to: position)
            }
            return .success
        }
        appendToDebugLog("[RCC] start() — isEnabled next=\(center.nextTrackCommand.isEnabled) prev=\(center.previousTrackCommand.isEnabled)")
    }

    func stop() async {
        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            #if os(macOS)
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            #endif
        }
        #if os(macOS)
        postDiscordRPC(.stopped)
        #endif
    }

    // MARK: - Update

    func update(with snapshot: NowPlayingSnapshot) async {
        if snapshot.isLiveStream {
            // Live stream: fresh dict with the IsLiveStream flag set.
            // Duration and elapsed time are intentionally omitted — Control Center hides
            // the scrubber automatically when MPNowPlayingInfoPropertyIsLiveStream is true.
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: snapshot.title,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
                MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
            ]
            if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
            let baseInfo = info
            await MainActor.run {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = baseInfo
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = .playing
                #endif
            }
            #if os(macOS)
            postDiscordRPC(.nowPlaying(.init(
                title: snapshot.title,
                artist: snapshot.artist ?? "",
                album: snapshot.album ?? "",
                duration: snapshot.duration,
                startedAt: Date().timeIntervalSince1970
            )))
            #endif

            // Check ArtworkImageCache — radio coverArtId maps to a server thumbnail when available.
            if let coverArtId = snapshot.coverArtId,
               let cachedImage = await artworkImageCache.cached(for: coverArtId) {
                let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in cachedImage }
                await MainActor.run {
                    var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? baseInfo
                    infoWithArt[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
                    #if os(macOS)
                    MPNowPlayingInfoCenter.default().playbackState = .playing
                    #endif
                }
            }

            updateRemoteCommandsAvailability(isLiveStream: true)
            return
        }

        updateRemoteCommandsAvailability(isLiveStream: false)

        if snapshot.artworkURL == nil {
            // Position-only update (pause/resume/seek): merge into the existing dict so
            // artwork already loaded for the current track is preserved.
            await MainActor.run {
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyTitle] = snapshot.title
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = snapshot.position
                info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
                info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.playbackRate
                info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
                if let album = snapshot.album { info[MPMediaItemPropertyAlbumTitle] = album }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
                #endif
            }
            #if os(macOS)
            if snapshot.playbackRate == 0 {
                postDiscordRPC(.stopped)
            }
            #endif
            return
        }

        // New track: build from scratch so stale artwork from the previous track is cleared
        // before the new one loads. Text metadata is committed first so the lockscreen
        // doesn't flash empty while the artwork fetch is in progress.
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.position,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = snapshot.album { info[MPMediaItemPropertyAlbumTitle] = album }
        let baseInfo = info
        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = baseInfo
            #if os(macOS)
            MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
            #endif
        }
        #if os(macOS)
        postDiscordRPC(.nowPlaying(.init(
            title: snapshot.title,
            artist: snapshot.artist ?? "",
            album: snapshot.album ?? "",
            duration: snapshot.duration,
            startedAt: Date().timeIntervalSince1970
        )))
        #endif

        // Fast path: image already in ArtworkImageCache (pre-loaded when the card was visible).
        if let coverArtId = snapshot.coverArtId,
           let cachedImage = await artworkImageCache.cached(for: coverArtId) {
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in cachedImage }
            let fallback = baseInfo
            await MainActor.run {
                var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? fallback
                infoWithArt[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
                #endif
            }
            return
        }

        // Slow path: fetch from URL and populate both caches.
        if let artworkURL = snapshot.artworkURL,
           let artwork = await artworkLoader.artwork(for: artworkURL, headers: snapshot.artworkHeaders) {
            let fallback = baseInfo
            await MainActor.run {
                var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? fallback
                infoWithArt[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
                #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = snapshot.playbackRate > 0 ? .playing : .paused
                #endif
            }
        }
    }

    // MARK: - Periodic position push

    func pushPosition(elapsed: TimeInterval, rate: Float, duration: TimeInterval) async {
        guard elapsed >= 0, duration > 0, elapsed <= duration else { return }
        await MainActor.run {
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            info[MPNowPlayingInfoPropertyPlaybackRate] = rate
            info[MPMediaItemPropertyPlaybackDuration] = duration
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            #if os(macOS)
            MPNowPlayingInfoCenter.default().playbackState = .playing
            #endif
        }
    }

    // MARK: - Remote command availability

    private func updateRemoteCommandsAvailability(isLiveStream: Bool) {
        let center = MPRemoteCommandCenter.shared()
        // Skip, previous, and scrubbing are meaningless for a live stream.
        // play/pause/togglePlayPause remain enabled in both modes (always-on).
        Logger.nowPlaying.debug("[REMOTE] updateRemoteCommandsAvailability — isLiveStream=\(isLiveStream, privacy: .public) nextEnabled=\(!isLiveStream, privacy: .public)")
        Logger.nowPlaying.debug("[REMOTE] nextTrackCommand.isEnabled BEFORE=\(center.nextTrackCommand.isEnabled, privacy: .public)")
        Logger.nowPlaying.debug("[REMOTE] previousTrackCommand.isEnabled BEFORE=\(center.previousTrackCommand.isEnabled, privacy: .public)")
        appendToDebugLog("[RCC] updateRemoteCommandsAvailability called — isLiveStream=\(isLiveStream)")
        appendToDebugLog("[RCC] nextTrack BEFORE=\(center.nextTrackCommand.isEnabled)")
        appendToDebugLog("[RCC] previousTrack BEFORE=\(center.previousTrackCommand.isEnabled)")
        center.nextTrackCommand.isEnabled = !isLiveStream
        center.previousTrackCommand.isEnabled = !isLiveStream
        #if os(macOS)
        center.skipBackwardCommand.isEnabled = !isLiveStream
        #endif
        center.changePlaybackPositionCommand.isEnabled = !isLiveStream
        Logger.nowPlaying.debug("[REMOTE] nextTrackCommand.isEnabled AFTER=\(center.nextTrackCommand.isEnabled, privacy: .public)")
        Logger.nowPlaying.debug("[REMOTE] previousTrackCommand.isEnabled AFTER=\(center.previousTrackCommand.isEnabled, privacy: .public)")
        appendToDebugLog("[RCC] nextTrack AFTER=\(center.nextTrackCommand.isEnabled)")
        appendToDebugLog("[RCC] previousTrack AFTER=\(center.previousTrackCommand.isEnabled)")
    }

    // MARK: - Discord RPC

    #if os(macOS)
    private nonisolated func postDiscordRPC(_ event: DiscordRPCEvent) {
        let port = 47832
        let urlString: String
        var body: Data?

        switch event {
        case .nowPlaying(let info):
            urlString = "http://localhost:\(port)/now-playing"
            body = try? JSONEncoder().encode(info)
        case .stopped:
            urlString = "http://localhost:\(port)/playback-stopped"
        }

        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
    #endif

    private func appendToDebugLog(_ message: String) {
        #if os(iOS)
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }
        let file = docs.appendingPathComponent("cassette_debug.log")
        let line = "\(Date()): \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: file.path) {
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
        #endif
    }
}

#if os(macOS)
private nonisolated enum DiscordRPCEvent {
    case nowPlaying(DiscordNowPlayingInfo)
    case stopped
}

private nonisolated struct DiscordNowPlayingInfo: Encodable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let startedAt: Double
}
#endif
