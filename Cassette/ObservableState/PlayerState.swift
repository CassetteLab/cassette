// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
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
}
