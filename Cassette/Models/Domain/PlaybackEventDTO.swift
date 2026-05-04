// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the GNU General Public License v3.0 or later.
// See LICENSE file in the project root for full license information.

import Foundation

/// Sendable value type used to transfer playback event data across actor boundaries.
///
/// PersistentModel instances (PlaybackEvent) must never cross actor boundaries —
/// this DTO carries the same data as a safe Sendable struct.
nonisolated struct PlaybackEventDTO: Sendable {
    let trackId: String
    let trackTitle: String
    let albumId: String?
    let albumTitle: String?
    let artistId: String?
    let artistName: String
    let genre: String?
    let timestamp: Date
    let durationListened: TimeInterval
    let trackDuration: TimeInterval
    let wasCompleted: Bool
    let serverId: String
}
