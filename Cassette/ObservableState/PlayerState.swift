import Foundation
import Observation
import SwiftSonic

/// Observable UI state for playback. Updated by PlayerService via MainActor.run.
/// Single source of truth consumed by MiniPlayer, FullPlayer, NowPlayingService,
/// and (v1.2) CarPlay scene — no duplicated playback state anywhere else.
@Observable
@MainActor
final class PlayerState {
    var currentTrack: Song?
    var queue: [Song] = []
    var currentIndex: Int = 0
    var playbackState: PlaybackState = .idle
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var repeatMode: RepeatMode = .off
    var isShuffled: Bool = false
}
