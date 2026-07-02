// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

protocol PlayerServiceProtocol: AnyObject, Sendable {
    /// Observable playback state (MainActor-isolated).
    /// Consumed by MiniPlayer, FullPlayer, NowPlayingService, and (v1.2) CarPlay scene.
    /// Never duplicate this state in a view model.
    var state: PlayerState { get }

    func play(tracks: [DisplayableSong], startIndex: Int) async throws
    /// Plays the given tracks in shuffled order and marks the session shuffled in one step, so the
    /// queue's shuffle toggle reflects ON immediately. Preserves the original (unshuffled) order so
    /// the toggle can restore it. Replaces the current queue. Empty input is a no-op.
    func playShuffled(tracks: [DisplayableSong]) async throws
    func resume() async
    func pause() async
    func stop() async
    func skipToNext() async throws
    func skipToPrevious() async throws
    func seek(to position: TimeInterval) async
    func setRepeatMode(_ mode: RepeatMode) async
    func toggleShuffle() async
    func appendToQueue(_ tracks: [DisplayableSong]) async
    func playNext(_ song: DisplayableSong) async
    func playNext(_ songs: [DisplayableSong]) async
    func addToQueue(_ song: DisplayableSong) async
    func addToQueue(_ songs: [DisplayableSong]) async
    func removeFromQueue(at index: Int) async
    func moveInQueue(fromIndex: Int, toIndex: Int) async
    func restoreSession() async
    func handleNetworkRestored() async
    /// Starts live stream playback of an Internet Radio Station.
    /// Clears the current queue's playing state but preserves the queue itself.
    func playRadio(_ station: InternetRadioStation) async throws
    /// Builds a Smart Shuffle queue via LibraryService and starts playback. Replaces the current queue.
    /// Throws `CassetteError.smartShuffleEmpty` if no eligible tracks (library too small / no downloads offline).
    func playSmartShuffle() async throws
    /// Toggles the auto-extend preference and persists it to UserDefaults.
    /// When enabled and ≤15 tracks remain, the player appends a fresh smart shuffle batch automatically.
    func setAutoExtendEnabled(_ enabled: Bool) async
    /// Applies the given volume (0.0–1.0) to AVPlayer and persists it to UserDefaults.
    func setVolume(_ volume: Float) async
    func togglePlayPause() async
    /// Lightweight position-only flush — called from scenePhase .inactive on iOS.
    func saveCurrentPosition() async
    /// Re-reads ReplayGainSettings and reapplies gain to the current track.
    /// Call this whenever the user changes any ReplayGain setting.
    func replayGainSettingsDidChange() async
    /// Updates the stored CrossfadeConfig snapshot from CrossfadeSettings.
    /// Call whenever the user changes any crossfade setting.
    func crossfadeSettingsDidChange() async
    /// Stops the audio engine synchronously without going through the actor.
    /// Only safe to call during app termination (single-threaded, no concurrent access).
    nonisolated func stopAudioEngineSync()
}
