// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import AVFoundation
import SwiftSonic
import OSLog

actor PlayerService: PlayerServiceProtocol {
    nonisolated let state: PlayerState

    private let mediaResolver: any MediaResolverProtocol
    private let serverService: any ServerServiceProtocol
    private var player: AVPlayer?

    init(
        state: PlayerState,
        mediaResolver: any MediaResolverProtocol,
        serverService: any ServerServiceProtocol
    ) {
        self.state = state
        self.mediaResolver = mediaResolver
        self.serverService = serverService
    }

    func play(tracks: [Song], startIndex: Int) async throws {
        // TODO: implement in Étape 4
        // 1. Call mediaResolver.resolve(songId:serverId:) → MediaSource
        // 2. Build AVPlayerItem with AVURLAsset(url:options:)
        //    For .stream, pass customHeaders via AVURLAssetHTTPHeaderFieldsKey.
        //    Note: AVURLAssetHTTPHeaderFieldsKey is publicly documented as of iOS 10 and
        //    consistently accepted in App Store review. Verified safe on iOS 17+ target.
        //    Monitor Apple release notes for changes to this API.
        // 3. Start playback, update state on MainActor
    }

    func resume() async {
        // TODO: implement in Étape 4
    }

    func pause() async {
        // TODO: implement in Étape 4
    }

    func stop() async {
        player?.pause()
        player = nil
        await MainActor.run {
            state.playbackState = .idle
            state.currentTrack = nil
            state.queue = []
            state.position = 0
        }
    }

    func skipToNext() async throws {
        // TODO: implement in Étape 4
    }

    func skipToPrevious() async throws {
        // TODO: implement in Étape 4
    }

    func seek(to position: TimeInterval) async {
        // TODO: implement in Étape 4
    }

    func setRepeatMode(_ mode: RepeatMode) async {
        await MainActor.run { state.repeatMode = mode }
    }

    func toggleShuffle() async {
        await MainActor.run { state.isShuffled.toggle() }
    }

    func appendToQueue(_ tracks: [Song]) async {
        await MainActor.run { state.queue.append(contentsOf: tracks) }
    }

    func removeFromQueue(at index: Int) async {
        await MainActor.run {
            guard state.queue.indices.contains(index) else { return }
            state.queue.remove(at: index)
        }
    }

    func moveInQueue(fromIndex: Int, toIndex: Int) async {
        // TODO: implement in Étape 4
    }
}
