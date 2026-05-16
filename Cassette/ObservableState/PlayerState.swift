// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Observation
import SwiftSonic

/// Observable UI state for playback. Updated by PlayerService via MainActor.run.
/// Single source of truth consumed by MiniPlayer, FullPlayer, NowPlayingService,
/// and (v1.2) CarPlay scene — no duplicated playback state anywhere else.
@Observable
@MainActor
final class PlayerState {
    var currentTrack: DisplayableSong?
    var queue: [DisplayableSong] = []
    var currentIndex: Int = 0
    var playbackState: PlaybackState = .idle
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var repeatMode: RepeatMode = .off
    var isShuffled: Bool = false
    /// False when a restored track cannot be resolved (offline + streamed only).
    /// Resets to true when normal playback starts.
    var isPlaybackAvailable: Bool = true
    /// Non-nil when the player is in live stream mode (radio playback).
    /// Mutually exclusive with active queue playback: starting play(tracks:) clears this to nil.
    var currentRadio: InternetRadioStation?
    /// True when a radio is the current playback source. Equivalent to currentRadio != nil.
    var isLiveStream: Bool { currentRadio != nil }
    /// True when the current playback session was started via Smart Shuffle.
    /// Survives skips and pauses; resets on new explicit play, radio, stop, or cold start.
    var isSmartShuffleActive: Bool = false
    /// User preference: when enabled, the player automatically appends a fresh smart shuffle batch
    /// when ≤15 tracks remain. Suppressed by loop mode and live stream mode. Persisted in UserDefaults.
    var isAutoExtendEnabled: Bool = UserDefaults.standard.bool(forKey: "cassette.player.autoExtendEnabled")
    /// Boundary between user-intentional queue tracks and auto-extended tracks.
    /// `nil` when no auto-extend has occurred in the current session.
    /// When set, indices `[0..<originalQueueEndIndex]` are user-intentional (album, playlist, or initial
    /// smart shuffle batch), and indices `[originalQueueEndIndex...]` are added by auto-extend.
    /// Reset to `nil` on play(tracks:), playRadio(), stop().
    var originalQueueEndIndex: Int?

    // MARK: - Derived UI state

    /// SF Symbol name and active-mode flag for the queue button, in priority order:
    /// Loop One > Loop All > Shuffle > Smart Shuffle > default queue list.
    /// Used by macOS "Up Next" header icon swap.
    var queueIcon: (symbolName: String, isActiveMode: Bool) {
        if repeatMode == .one    { return ("repeat.1", true) }
        if repeatMode == .all    { return ("repeat",   true) }
        if isShuffled            { return ("shuffle",  true) }
        if isSmartShuffleActive  { return ("sparkles", true) }
        return ("list.bullet", false)
    }

    /// Badge symbol to overlay on the iOS queue icon, or nil when no mode is active.
    /// Priority: Loop One > Loop All > Shuffle > Smart Shuffle.
    var queueModeBadge: String? {
        if repeatMode == .one   { return "repeat.1" }
        if repeatMode == .all   { return "repeat" }
        if isShuffled           { return "shuffle" }
        if isSmartShuffleActive { return "sparkles" }
        return nil
    }
}
