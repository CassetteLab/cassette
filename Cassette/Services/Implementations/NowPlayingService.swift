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

    init(playerService: any PlayerServiceProtocol) {
        self.playerService = playerService
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

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
        if snapshot.artworkURL == nil {
            // Position-only update (pause/resume/seek): merge into the existing dict so
            // artwork already loaded for the current track is preserved.
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyTitle] = snapshot.title
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = snapshot.position
            info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
            info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.playbackRate
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
            if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
            if let album = snapshot.album { info[MPMediaItemPropertyAlbumTitle] = album }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let artworkURL = snapshot.artworkURL,
           let artwork = await artworkLoader.artwork(for: artworkURL, headers: snapshot.artworkHeaders) {
            var infoWithArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
            infoWithArt[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = infoWithArt
        }
    }
}
