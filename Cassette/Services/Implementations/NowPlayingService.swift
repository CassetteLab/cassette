// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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

    init(playerService: any PlayerServiceProtocol, artworkImageCache: ArtworkImageCache) {
        self.playerService = playerService
        self.artworkImageCache = artworkImageCache
    }

    // MARK: - Lifecycle

    func start() async {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { await self.playerService.resume() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { await self.playerService.pause() }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task {
                let state = await self.playerService.state.playbackState
                if state == .playing {
                    await self.playerService.pause()
                } else {
                    await self.playerService.resume()
                }
            }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { try? await self.playerService.skipToNext() }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { try? await self.playerService.skipToPrevious() }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let seekEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { await self.playerService.seek(to: seekEvent.positionTime) }
            return .success
        }
    }

    func stop() async {
        await MainActor.run { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
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
            await MainActor.run { MPNowPlayingInfoCenter.default().nowPlayingInfo = baseInfo }

            // Check ArtworkImageCache — radio coverArtId maps to a server thumbnail when available.
            if let coverArtId = snapshot.coverArtId,
               let cachedImage = await artworkImageCache.cached(for: coverArtId) {
                let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in cachedImage }
                await MainActor.run {
                    var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? baseInfo
                    infoWithArt[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
                }
            }

            updateRemoteCommandsAvailability(isLiveStream: true)
            return
        }

        updateRemoteCommandsAvailability(isLiveStream: false)

        if snapshot.artworkURL == nil {
            // Position-only update (pause/resume/seek): merge into the existing dict so
            // artwork already loaded for the current track is preserved.
            let ts = Date().timeIntervalSince1970
            Logger.nowPlayingDebug.debug("[MPNOW-PUSH position-only] elapsed=\(snapshot.position, format: .fixed(precision: 3))s rate=\(snapshot.playbackRate, format: .fixed(precision: 1)) duration=\(snapshot.duration, format: .fixed(precision: 3))s ts=\(ts, format: .fixed(precision: 3))")
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
            }
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
        let newTrackTs = Date().timeIntervalSince1970
        Logger.nowPlayingDebug.debug("[MPNOW-PUSH new-track] elapsed=\(snapshot.position, format: .fixed(precision: 3))s rate=\(snapshot.playbackRate, format: .fixed(precision: 1)) duration=\(snapshot.duration, format: .fixed(precision: 3))s ts=\(newTrackTs, format: .fixed(precision: 3))")
        await MainActor.run { MPNowPlayingInfoCenter.default().nowPlayingInfo = baseInfo }

        // Fast path: image already in ArtworkImageCache (pre-loaded when the card was visible).
        if let coverArtId = snapshot.coverArtId,
           let cachedImage = await artworkImageCache.cached(for: coverArtId) {
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in cachedImage }
            let fallback = baseInfo
            await MainActor.run {
                var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? fallback
                infoWithArt[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
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
            }
        }
    }

    // MARK: - Remote command availability

    private func updateRemoteCommandsAvailability(isLiveStream: Bool) {
        let center = MPRemoteCommandCenter.shared()
        // Skip, previous, and scrubbing are meaningless for a live stream.
        // play/pause/togglePlayPause remain enabled in both modes (always-on).
        center.nextTrackCommand.isEnabled = !isLiveStream
        center.previousTrackCommand.isEnabled = !isLiveStream
        center.changePlaybackPositionCommand.isEnabled = !isLiveStream
    }
}
