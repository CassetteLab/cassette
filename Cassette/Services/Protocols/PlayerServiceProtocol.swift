// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

protocol PlayerServiceProtocol: AnyObject, Sendable {
    /// Observable playback state (MainActor-isolated).
    /// Consumed by MiniPlayer, FullPlayer, NowPlayingService, and (v1.2) CarPlay scene.
    /// Never duplicate this state in a view model.
    var state: PlayerState { get }

    func play(tracks: [Song], startIndex: Int) async throws
    func resume() async
    func pause() async
    func stop() async
    func skipToNext() async throws
    func skipToPrevious() async throws
    func seek(to position: TimeInterval) async
    func setRepeatMode(_ mode: RepeatMode) async
    func toggleShuffle() async
    func appendToQueue(_ tracks: [Song]) async
    func removeFromQueue(at index: Int) async
    func moveInQueue(fromIndex: Int, toIndex: Int) async
}
